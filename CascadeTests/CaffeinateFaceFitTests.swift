//
//  CaffeinateFaceFitTests.swift
//  CascadeTests
//

import CascadeContracts
@testable import CascadePlugins
import CascadePluginSDK
import Foundation
import SwiftUI
import Testing
@testable import Cascade
@testable import CascadeKit
@testable import CascadePluginEngine

/// CaffeinateFaceFitTests renders Caffeinate's documents the way the notch draws them. The
/// widget is a `ViewThatFits` of a large and a small face, and that view picks the first face
/// whose ideal width fits the tile: a face that is too wide is never chosen, and the widget
/// would silently show only its disc in every size. The options page has no such fallback and
/// must simply fit the notch's interior.
@MainActor
@Suite("Caffeinate face fit")
struct CaffeinateFaceFitTests {

    /// The widget's tiles in the default notch: 400 points of interior width, a 2x1 tile 110
    /// points wide and a 1x1 tile 52, both 40 high.
    private static let interior     = CGRect(x: 0, y: 0, width: 400, height: 124)
    private static let optionsFrame = CGSize(width: 400, height: 86)

    private static let owner = PluginID(rawValue: "com.cascade.caffeinate")!
    private static let key   = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)

    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private static var states: [(name: String, state: PluginCaffeinateState)] {
        [
            ("off", PluginCaffeinateState()),
            (
                "timed",
                PluginCaffeinateState(
                    startedAt        : moment,
                    endsAt           : moment.addingTimeInterval(1_440 * 60),
                    activityStartedAt: moment
                )
            ),
            (
                "indefinite",
                PluginCaffeinateState(
                    startedAt        : moment,
                    activityStartedAt: moment
                )
            ),
        ]
    }

    @Test
    func eachFaceFitsTheTileItIsChosenFor() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == Self.owner })

        for (name, state) in Self.states {
            let document = try publish(state)
            let faces    = document.root.children
            #expect(document.root.kind == .viewThatFits(axes: .horizontal), "\(name)")
            try #require(faces.count == 2)

            let host   = SurfaceFixture()
            let router = PluginSurfaceRouter(
                host      : host,
                manifests : [manifest],
                submit    : { _ in },
                visibility: { _, _ in }
            )
            var store  = PluginPublicationStore()
            let change = store.apply(document, staleAfter: nil, for: Self.key, at: .now)
            router.apply([try #require(change)], rejected: [])
            let widget = try #require(host.widget)
            #expect(widget.sizes == [GridSpan(columns: 4, rows: 1), GridSpan(columns: 2, rows: 1)], "\(name)")

            let large     = try tile(widget.sizes[0], of: widget.id)
            let small     = try tile(widget.sizes[1], of: widget.id)
            let largeFace = idealSize(of: try PluginDocument(root: faces[0]))
            let smallFace = idealSize(of: try PluginDocument(root: faces[1]))

            #expect(largeFace.width <= large.width, "\(name): the large face is wider than its 2x1 tile")
            #expect(largeFace.height <= large.height, "\(name): the large face is taller than its 2x1 tile")
            #expect(largeFace.width > small.width, "\(name): the 1x1 tile would show the large face")
            #expect(smallFace.width <= small.width, "\(name): the small face is wider than its 1x1 tile")
            #expect(smallFace.height <= small.height, "\(name): the small face is taller than its 1x1 tile")

            #expect(containsText(CaffeinateStyle.Copy.title, in: faces[0]), "\(name): the 2x1 tile shows no title")
            #expect(!containsText(CaffeinateStyle.Copy.title, in: faces[1]), "\(name): the 1x1 tile shows a title")
        }
    }

    @Test
    func theOptionsPageFitsTheExpandedNotchInEveryState() throws {
        for (name, state) in Self.states {
            let document = try publish(state)
            let options  = try #require(document.optionsRoot)
            let page     = try PluginDocument(root: options)

            let natural = idealSize(of: page)
            #expect(natural.width <= Self.optionsFrame.width, "\(name): the options page asks for \(natural.width) points of width")

            let fitted = idealSize(of: page, width: Self.optionsFrame.width)
            #expect(fitted.height <= Self.optionsFrame.height, "\(name): the options page needs \(fitted.height) points of height")
        }
    }

    // MARK: - Helpers

    private func publish(_ state: PluginCaffeinateState) throws -> PluginDocument {
        let output = try CaffeinatePlugin().handle(
            .source(state.event()),
            context: PluginContext(plugin: Self.owner)
        )

        return try #require(output.publications.first { $0.surface == .widget }?.document)
    }

    private func containsText(
        _ text: String,
        in node: PluginNode
    ) -> Bool {
        if node.kind == .text(text) { return true }

        return node.children.contains { containsText(text, in: $0) }
    }

    private func nodeStore(_ document: PluginDocument) throws -> PluginNodeStore {
        var publisher = PluginPublicationStore()
        let store     = PluginNodeStore(key: Self.key, submit: { _ in })
        let change    = publisher.apply(document, staleAfter: nil, for: Self.key, at: .now)
        store.apply(try #require(change))

        return store
    }

    /// idealSize is the size a document asks for when nothing constrains it, or only its width.
    /// An unspecified proposal is the one `ViewThatFits` measures a face with: a flexible frame
    /// then reports its content's ideal size instead of whatever it is offered.
    private func idealSize(
        of document: PluginDocument,
        width      : CGFloat? = nil
    ) -> CGSize {
        let store    = (try? nodeStore(document)) ?? PluginNodeStore(key: Self.key, submit: { _ in })
        let renderer = ImageRenderer(content: PluginDocumentView(store: store).environment(\.colorScheme, .dark))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale        = 1

        return renderer.nsImage?.size ?? CGSize(width: CGFloat.infinity, height: .infinity)
    }

    private func tile(
        _ span: GridSpan,
        of id : WidgetIdentifier
    ) throws -> CGRect {
        let layout = NotchLayoutResolver().resolve(
            interior     : Self.interior,
            notchWidth   : 0,
            topBandHeight: 32,
            placements   : [id: WidgetPlacement(position: GridPosition(column: 0, row: 1), span: span)]
        )

        return try #require(layout.frames[id])
    }

    @MainActor
    private final class SurfaceFixture: PluginSurfaceHosting {

        var widget: (any NotchWidget)?

        func register(_ widget: any NotchWidget) { self.widget = widget }
        func unregisterWidget(id: WidgetIdentifier) { widget = nil }
        func showNotice(_ notice: any NotchTransientNotice) {}
        func updateNotice(_ notice: any NotchTransientNotice) {}
        func dismissActivity(id: String) {}
        func present(_ activity: any NotchLiveActivity) {}
        func endActivity(id: String) {}
    }
}
