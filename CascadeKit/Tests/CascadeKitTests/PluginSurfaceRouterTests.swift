//
//  PluginSurfaceRouterTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginSurfaceRouterTests {

    private let clock = PluginID(rawValue: "com.cascade.clock")!

    private var widgetKey: PluginPublicationKey {
        PluginPublicationKey(plugin: clock, feature: "time", surface: .widget)
    }

    private var widgetID: WidgetIdentifier {
        WidgetIdentifier("plugin:com.cascade.clock/time")
    }

    private var alarmKey: PluginPublicationKey {
        PluginPublicationKey(plugin: clock, feature: "alarm", surface: .widget)
    }

    /// Rig is a router over a recording host, with what they submitted and reported.
    @MainActor
    final class Rig {

        let host      = RecordingSurfaceHost()
        var submitted : [PluginActionRequest] = []
        var visibility: [(Bool, PluginPublicationKey)] = []
        var surfaces  : PluginSurfaceRouter!
    }

    private func rig() throws -> Rig {
        let rig      = Rig()
        let manifest = try PluginManifest(
            manifestVersion: 2,
            id             : clock,
            version        : "1.0.0",
            compatibility  : PluginCompatibility(macOS: "15.0", cascadeProtocol: PluginProtocolVersion(major: 2, minimumMinor: 0)),
            execution      : PluginExecution(entryPoint: "ClockPlugin"),
            sourceApp      : nil,
            requires       : [],
            features       : [
                PluginFeature(id: "time", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 3, rows: 1)]))),
                PluginFeature(id: "alarm", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 1), PluginWidgetSize(columns: 2, rows: 2)]))),
            ],
            resources      : PluginResources(profile: .eventDriven)
        )
        rig.surfaces = PluginSurfaceRouter(
            host      : rig.host,
            manifests : [manifest],
            submit    : { [unowned rig] in rig.submitted.append($0) },
            visibility: { [unowned rig] isVisible, key in rig.visibility.append((isVisible, key)) }
        )
        return rig
    }

    private func publish(
        _ document  : PluginDocument,
        in publisher: inout PluginPublicationStore,
        for key     : PluginPublicationKey? = nil
    ) -> PluginPublicationChange {
        let key = key ?? widgetKey

        return publisher.apply(document, staleAfter: nil, for: key, at: Date()) ?? PluginPublicationChange(key: key, revision: 0, content: nil)
    }

    @Test
    func theFirstContentRegistersOneWidget() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])

        let widget = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        #expect(rig.host.registrations == 1)
        #expect(widget.store.root?.kind == .clock)
    }

    @Test
    func theWidgetTakesItsDeclaredSize() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])

        #expect(rig.host.widgets[widgetID]?.size == GridSpan(columns: 6, rows: 1))
    }

    @Test
    func theWidgetOffersEveryDeclaredSizeInTheManifestsOrder() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher, for: alarmKey)], rejected: [])

        let alarm = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/alarm")])
        #expect(alarm.sizes == [GridSpan(columns: 2, rows: 1), GridSpan(columns: 4, rows: 2)])
        #expect(alarm.size == GridSpan(columns: 2, rows: 1))
    }

    @Test
    func laterChangesUpdateTheSameWidget() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.text("One"))), in: &publisher)], rejected: [])

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.text("Two"))), in: &publisher)], rejected: [])

        let widget = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        #expect(rig.host.registrations == 1)
        #expect(widget.store.root?.kind == .text("Two"))
    }

    @Test
    func aWithdrawalRemovesTheWidget() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])
        let withdrawn  = publisher.withdraw(widgetKey)
        let withdrawal = try #require(withdrawn)

        rig.surfaces.apply([withdrawal], rejected: [])

        #expect(rig.host.widgets.isEmpty)
    }

    @Test
    func activationAndSuspensionReportVisibility() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])
        let widget = try #require(rig.host.widgets[widgetID])

        widget.activate(in: WidgetContext(state: .open, requestContent: {}))
        widget.suspend()

        #expect(rig.visibility.map(\.0) == [true, false])
        #expect(rig.visibility.allSatisfy { $0.1 == widgetKey })
    }

    @Test
    func aRefusalRevertsItsControlAndNoOther() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let toggle    = try PluginDocument(root: PluginNode(.toggle(isOn: true, action: "flip"), id: "flip"))
        rig.surfaces.apply([publish(toggle, in: &publisher), publish(toggle, in: &publisher, for: alarmKey)], rejected: [])
        let time  = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        let alarm = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/alarm")] as? PluginWidget)
        let flip  = PluginNodeID(rawValue: "#flip:toggle")
        let timeToggle  = try #require(time.store.model(flip))
        let alarmToggle = try #require(alarm.store.model(flip))
        time.store.set(.bool(false), on: timeToggle)
        alarm.store.set(.bool(false), on: alarmToggle)

        rig.surfaces.apply([], rejected: [try #require(rig.submitted.first { $0.key == alarmKey })])

        #expect(timeToggle.optimistic == .bool(false))
        #expect(alarmToggle.optimistic == nil)
    }

    @Test
    func explicitCompactRegionWidthsAvoidTheDefaultEmptyWings() throws {
        let rig = try rig()
        let key = PluginPublicationKey(plugin: clock, feature: "time", surface: .activity)
        let document = try PluginDocument(root: PluginNode(.regions, children: [
            PluginNode(.symbol(name: "record.circle"), modifiers: [.frame(width: 20, height: nil, maxWidth: nil, maxHeight: nil, alignment: .center)]),
            PluginNode(.text("00:00"), modifiers: [.frame(width: 36, height: nil, maxWidth: nil, maxHeight: nil, alignment: .center)]),
            PluginNode(.text("")),
            PluginNode(.text("Recording")),
        ]))
        var publisher = PluginPublicationStore()
        let applied = publisher.apply(document, staleAfter: nil, for: key, at: Date())
        let change = try #require(applied)
        rig.surfaces.apply([change], rejected: [])

        #expect(rig.host.activities.values.first?.compactPreferredSideWidth == 50)
    }

    @Test
    func anActivityReachesTheHostAndWithdrawsWhenRecordingEnds() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let key       = PluginPublicationKey(plugin: clock, feature: "time", surface: .activity)
        let applied   = publisher.apply(try PluginDocument(root: PluginNode(.clock)), staleAfter: nil, for: key, at: Date())
        let change    = try #require(applied)

        rig.surfaces.apply([change], rejected: [])

        #expect(rig.host.widgets.isEmpty)
        #expect(rig.host.activities.count == 1)

        let withdrawn = publisher.withdraw(key)
        rig.surfaces.apply([try #require(withdrawn)], rejected: [])

        #expect(rig.host.activities.isEmpty)
        #expect(rig.host.dismissed == ["plugin:com.cascade.clock/time/activity"])
    }

    @Test
    func aNoticeAndActivityOfOneFeatureKeepSeparateIdentities() throws {
        let rig = try rig()
        var publisher = PluginPublicationStore()
        let activityKey = PluginPublicationKey(plugin: clock, feature: "time", surface: .activity)
        let noticeKey = PluginPublicationKey(plugin: clock, feature: "time", surface: .notice)
        let activityChange = publisher.apply(try PluginDocument(root: PluginNode(.text("Recording"))), staleAfter: nil, for: activityKey, at: Date())
        let regions = try PluginDocument(root: PluginNode(.regions, children: [PluginNode(.text("Saved")), PluginNode(.text("")), PluginNode(.text("Saved"))]))
        let attributes = try PluginNoticeAttributes(duration: 4, accessibilityLabel: "Saved")
        let noticeChange = publisher.apply(regions, staleAfter: nil, for: noticeKey, at: Date(), notice: attributes)
        rig.surfaces.apply([try #require(activityChange), try #require(noticeChange)], rejected: [])
        let activity = try #require(rig.host.activities.values.first)
        let notice = try #require(rig.host.shown.last?.notice)

        #expect(activity.id != notice.id)
        let liveHost = LiveActivityHost()
        liveHost.present(activity)
        liveHost.showNotice(notice)
        #expect(liveHost.selection.primary === activity)
        liveHost.dismiss(id: notice.id)
        #expect(liveHost.selection.primary === activity)
        let withdrawn = publisher.withdraw(noticeKey)
        rig.surfaces.apply([try #require(withdrawn)], rejected: [])
        #expect(rig.host.activities.values.first === activity)
    }

    @Test
    func activityUpdatesKeepTheirLifetimeAndReportVisibility() throws {
        let rig = try rig()
        var publisher = PluginPublicationStore()
        let key = PluginPublicationKey(plugin: clock, feature: "time", surface: .activity)
        let first = publisher.apply(try PluginDocument(root: PluginNode(.text("Recording"))), staleAfter: nil, for: key, at: Date())
        rig.surfaces.apply([try #require(first)], rejected: [])
        let activity = try #require(rig.host.activities.values.first)
        let lifetime = activity.lifetime
        let second = publisher.apply(try PluginDocument(root: PluginNode(.text("Stopping"))), staleAfter: nil, for: key, at: Date())
        rig.surfaces.apply([try #require(second)], rejected: [])

        #expect(rig.host.activities.values.first === activity)
        #expect(activity.lifetime == lifetime)
        #expect(activity.contentRevision == 2)
        activity.activate(in: LiveActivityContext(onInvalidate: {}))
        activity.suspend()
        #expect(rig.visibility.map(\.0) == [true, false])
    }
}
