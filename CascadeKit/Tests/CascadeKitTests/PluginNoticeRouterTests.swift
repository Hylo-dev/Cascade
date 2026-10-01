//
//  PluginNoticeRouterTests.swift
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
struct PluginNoticeRouterTests {

    private let power = PluginID(rawValue: "com.cascade.power")!

    private var key: PluginPublicationKey {
        PluginPublicationKey(plugin: power, feature: "charging", surface: .notice)
    }

    private func router(_ host: RecordingSurfaceHost) -> PluginSurfaceRouter {
        PluginSurfaceRouter(host: host, manifests: [], submit: { _ in }, visibility: { _, _ in })
    }

    private func notice(_ percent: String = "80%") throws -> (PluginDocument, PluginNoticeAttributes) {
        let document = try PluginDocument(
            root: PluginNode(
                .regions,
                children: [PluginNode(.text("Charging")), PluginNode(.text(percent)), PluginNode(.symbol(name: "battery.100percent"))]
            )
        )
        let attributes = try PluginNoticeAttributes(duration: 4, border: .charging, compactWidth: 116, accessibilityLabel: "Charging, \(percent)")

        return (document, attributes)
    }

    private func publish(
        _ notice    : (PluginDocument, PluginNoticeAttributes),
        in publisher: inout PluginPublicationStore
    ) throws -> PluginPublicationChange {
        let change = publisher.apply(notice.0, staleAfter: nil, for: key, at: Date(), notice: notice.1)

        return try #require(change)
    }

    @Test
    func aNoticeIsShownWithItsAttributes() throws {
        let host      = RecordingSurfaceHost()
        let router    = router(host)
        var publisher = PluginPublicationStore()

        router.apply([try publish(notice(), in: &publisher)], rejected: [])

        let shown = try #require(host.shown.first?.notice)
        #expect(host.shown.count == 1)
        #expect(shown.id == "plugin:com.cascade.power/charging")
        #expect(shown.sourceID == "com.cascade.power")
        #expect(shown.displayDuration == 4)
        #expect(shown.borderAppearance == .charging)
        #expect(shown.compactPreferredSideWidth == 116)
        #expect(shown.accessibilityLabel == "Charging, 80%")
    }

    @Test
    func anEqualNoticeIsShownAgain() throws {
        let host      = RecordingSurfaceHost()
        let router    = router(host)
        var publisher = PluginPublicationStore()

        router.apply([try publish(notice(), in: &publisher)], rejected: [])
        router.apply([try publish(notice(), in: &publisher)], rejected: [])

        #expect(host.shown.map(\.revision) == [1, 2])
        #expect(host.shown[0].notice === host.shown[1].notice)
    }

    @Test
    func aWithdrawnNoticeIsDismissed() throws {
        let host      = RecordingSurfaceHost()
        let router    = router(host)
        var publisher = PluginPublicationStore()
        router.apply([try publish(notice(), in: &publisher)], rejected: [])
        let withdrawn = publisher.withdraw(key)

        router.apply([try #require(withdrawn)], rejected: [])

        #expect(host.dismissed == ["plugin:com.cascade.power/charging"])
    }

    @Test
    func eachRegionDrawsItsOwnNode() throws {
        let host      = RecordingSurfaceHost()
        let router    = router(host)
        var publisher = PluginPublicationStore()
        router.apply([try publish(notice(), in: &publisher)], rejected: [])
        let shown   = try #require(host.shown.first?.notice)
        let context = NotchActivityViewContext(presentation: .compactLeading, availableSize: CGSize(width: 116, height: 24))
        let views   = [
            shown.makeCompactLeadingView(in: context),
            shown.makeCompactTrailingView(in: context),
            shown.makeMinimalView(in: context),
        ]

        for view in views {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 116, height: 24)
            hosting.layoutSubtreeIfNeeded()

            #expect(hosting.fittingSize.width > 0)
        }
        let notice = try #require(shown as? PluginNotice)
        #expect(notice.region(0)?.kind == .text("Charging"))
        #expect(notice.region(1)?.kind == .text("80%"))
        #expect(notice.region(2)?.kind == .symbol(name: "battery.100percent"))
    }
}
