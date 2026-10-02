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

    /// views are a notice's three factories, laid out in a compact slot.
    private func views() throws -> [NSHostingView<AnyView>] {
        let host      = RecordingSurfaceHost()
        let router    = router(host)
        var publisher = PluginPublicationStore()
        let document  = try PluginDocument(
            root: PluginNode(
                .regions,
                children: [PluginNode(.text("W")), PluginNode(.text("WWWWWWWW")), PluginNode(.text("WWWW"))]
            )
        )
        let attributes = try PluginNoticeAttributes(duration: 4, accessibilityLabel: "Notice")
        router.apply([try publish((document, attributes), in: &publisher)], rejected: [])
        let shown   = try #require(host.shown.first?.notice)
        let context = NotchActivityViewContext(presentation: .compactLeading, availableSize: CGSize(width: 160, height: 24))

        return [
            shown.makeCompactLeadingView(in: context),
            shown.makeCompactTrailingView(in: context),
            shown.makeMinimalView(in: context),
        ].map { view in
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 160, height: 24)
            hosting.layoutSubtreeIfNeeded()
            return hosting
        }
    }

    @Test
    func eachSlotDrawsItsOwnRegion() throws {
        let widths = try views().map(\.fittingSize.width)
        let alone  = ["W", "WWWWWWWW", "WWWW"].map { text in
            NSHostingView(rootView: Text(verbatim: text)).fittingSize.width
        }

        #expect(widths == alone)
    }

    @Test
    func anUpdateEnrichesTheNoticeWithoutShowingItAgain() throws {
        let host      = RecordingSurfaceHost()
        let router    = router(host)
        var publisher = PluginPublicationStore()
        let (document, shown) = try notice()
        let enriched  = try PluginNoticeAttributes(duration: 4, accessibilityLabel: "Charging, 81%", delivery: .update)
        router.apply([try publish((document, shown), in: &publisher)], rejected: [])

        router.apply([try publish((document, enriched), in: &publisher)], rejected: [])

        #expect(host.shown.count == 1)
        #expect(host.updated == [2])
        #expect(host.shown[0].notice.accessibilityLabel == "Charging, 81%")
    }
}
