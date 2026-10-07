//
//  PluginActivityRoutingTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginActivityRoutingTests {

    private let owner = PluginID(rawValue: "com.cascade.caffeinate")!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private var key: PluginPublicationKey {
        PluginPublicationKey(plugin: owner, feature: "caffeinate", surface: .activity)
    }

    /// Rig is a router over a recording host, with what it submitted and what its activity
    /// reported about its visibility.
    @MainActor
    private final class Rig {

        let host       = RecordingSurfaceHost()
        var publisher  = PluginPublicationStore()
        var submitted  : [PluginActionRequest] = []
        var visibility : [Bool] = []
        var surfaces   : PluginSurfaceRouter!

        init() {
            surfaces = PluginSurfaceRouter(
                host      : host,
                manifests : [],
                submit    : { [unowned self] in submitted.append($0) },
                visibility: { [unowned self] isVisible, _ in visibility.append(isVisible) }
            )
        }
    }

    private func regions(_ expanded: String = "Expanded") throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .regions,
                children: [
                    PluginNode(.text("W")),
                    PluginNode(.text("WWWWWWWW")),
                    PluginNode(.text("WWWW")),
                    PluginNode(.button(action: "stop"), id: "stop", children: [PluginNode(.text(expanded))]),
                ]
            )
        )
    }

    private func publish(
        _ rig     : Rig,
        document  : PluginDocument? = nil,
        startedAt : Date? = nil,
        relevance : Double = 0.3
    ) throws -> PluginPublicationChange {
        let attributes = try PluginActivityAttributes(startedAt: startedAt ?? start, relevance: relevance, accessibilityLabel: "Keeping awake")
        let change     = rig.publisher.apply(
            try document ?? regions(),
            staleAfter: nil,
            for       : key,
            at        : Date(),
            activity  : attributes
        )

        return try #require(change)
    }

    @Test
    func anActivityIsPresentedWithItsFirstContent() throws {
        let rig = Rig()

        rig.surfaces.apply([try publish(rig)], rejected: [])

        let presented = try #require(rig.host.presented.first)
        #expect(rig.host.presented.count == 1)
        #expect(presented.id == "plugin:com.cascade.caffeinate/caffeinate")
        #expect(presented.sourceID == "com.cascade.caffeinate")
        #expect(presented.lifetime == NotchActivityLifetime(startedAt: start))
        #expect(presented.relevanceScore == 0.3)
        #expect(presented.accessibilityLabel == "Keeping awake")
        #expect(presented.privacy == .standard)
        #expect(presented.contentRevision == 1)
    }

    @Test
    func anUpdateDoesNotPresentAgain() throws {
        let rig = Rig()
        rig.surfaces.apply([try publish(rig)], rejected: [])

        rig.surfaces.apply([try publish(rig, document: regions("Changed"))], rejected: [])

        let presented = try #require(rig.host.presented.first)
        #expect(rig.host.activityCalls == ["present"])
        #expect(presented.contentRevision == 2)
    }

    @Test
    func aChangedRelevancePresentsAgainWithoutEnding() throws {
        let rig = Rig()
        rig.surfaces.apply([try publish(rig)], rejected: [])

        rig.surfaces.apply([try publish(rig, relevance: 0.6)], rejected: [])

        let presented = try #require(rig.host.presented.first)
        #expect(rig.host.activityCalls == ["present", "present"])
        #expect(presented.relevanceScore == 0.6)
    }

    /// aRenewedStartPresentsAgain checks the order too: the host keeps an old entry's session
    /// deadline, so the old session must end before the renewed one is presented.
    @Test
    func aRenewedStartPresentsAgain() throws {
        let rig     = Rig()
        let renewed = start.addingTimeInterval(9 * 60 * 60)
        rig.surfaces.apply([try publish(rig)], rejected: [])

        rig.surfaces.apply([try publish(rig, startedAt: renewed)], rejected: [])

        #expect(rig.host.activityCalls == ["present", "end", "present"])
        #expect(rig.host.ended == ["plugin:com.cascade.caffeinate/caffeinate"])
        #expect(rig.host.presented[0] === rig.host.presented[1])
        #expect(rig.host.presented[1].lifetime == NotchActivityLifetime(startedAt: renewed))
    }

    /// LiveHost forwards the activity calls to a real LiveActivityHost, whose clock the test drives.
    @MainActor
    private final class LiveHost: PluginSurfaceHosting {

        let live: LiveActivityHost

        init(live: LiveActivityHost) { self.live = live }

        func register(_ widget: NotchWidget) {}
        func unregisterWidget(id: WidgetIdentifier) {}
        func showNotice(_ notice: any NotchTransientNotice) {}
        func updateNotice(_ notice: any NotchTransientNotice) {}
        func dismissActivity(id: String) {}
        func present(_ activity: any NotchLiveActivity) { live.present(activity) }
        func endActivity(id: String) { live.end(id: id) }
    }

    @Test
    func aRenewedStartGetsAFreshSessionDeadlineInTheRealHost() throws {
        var now        = start
        let live       = LiveActivityHost(now: { now })
        let surfaces   = PluginSurfaceRouter(host: LiveHost(live: live), manifests: [], submit: { _ in }, visibility: { _, _ in })
        var publisher  = PluginPublicationStore()
        let id         = "plugin:com.cascade.caffeinate/caffeinate"
        func publish(startedAt: Date) throws {
            let attributes = try PluginActivityAttributes(startedAt: startedAt, relevance: 0.3, accessibilityLabel: "Keeping awake")
            let change     = publisher.apply(try regions(), staleAfter: nil, for: key, at: now, activity: attributes)
            surfaces.apply([try #require(change)], rejected: [])
        }

        try publish(startedAt: start)
        now = start.addingTimeInterval(7 * 60 * 60)
        live.expireNotices()
        #expect(live.selection.primary?.id == id)

        try publish(startedAt: now)
        now = start.addingTimeInterval(8 * 60 * 60 + 60)
        live.expireNotices()
        #expect(live.selection.primary?.id == id)

        now = start.addingTimeInterval(15 * 60 * 60 + 60)
        live.expireNotices()
        #expect(live.selection.primary == nil)
    }

    @Test
    func aWithdrawalEndsTheActivity() throws {
        let rig = Rig()
        rig.surfaces.apply([try publish(rig)], rejected: [])
        let withdrawn = rig.publisher.withdraw(key)

        rig.surfaces.apply([try #require(withdrawn)], rejected: [])
        rig.surfaces.apply([try publish(rig)], rejected: [])

        #expect(rig.host.ended == ["plugin:com.cascade.caffeinate/caffeinate"])
        #expect(rig.host.presented.count == 2)
        #expect(rig.host.presented[0] !== rig.host.presented[1])
    }

    @Test
    func aWithdrawalOfWhatWasNeverPresentedEndsNothing() throws {
        let rig = Rig()
        let change = PluginPublicationChange(key: key, revision: 1, content: nil)

        rig.surfaces.apply([change], rejected: [])

        #expect(rig.host.ended.isEmpty)
    }

    @Test
    func theExpandedRegionIsTheFourth() throws {
        let rig = Rig()
        rig.surfaces.apply([try publish(rig)], rejected: [])
        let presented = try #require(rig.host.presented.first)
        let context   = NotchActivityViewContext(presentation: .expanded, availableSize: CGSize(width: 200, height: 40))

        let hosting = NSHostingView(rootView: presented.makeExpandedView(in: context))
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        hosting.layoutSubtreeIfNeeded()
        let fourth  = NSHostingView(rootView: Text(verbatim: "Expanded"))

        #expect(hosting.fittingSize.width == fourth.fittingSize.width)
    }

    @Test
    func activityControlsSubmitThroughTheBroker() throws {
        let rig = Rig()
        rig.surfaces.apply([try publish(rig)], rejected: [])
        let activity = try #require(rig.host.presented.first as? PluginActivity)
        let button   = try #require(activity.store.model(PluginNodeID(rawValue: "#stop:button")))

        activity.store.press(button)

        #expect(rig.submitted == [PluginActionRequest(key: key, node: button.id, revision: 1)])
    }

    @Test
    func theActivityReportsItsVisibility() throws {
        let rig = Rig()
        rig.surfaces.apply([try publish(rig)], rejected: [])
        let presented = try #require(rig.host.presented.first)

        presented.suspend()

        #expect(rig.visibility == [false])
    }
}
