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
/// widget is a `ViewThatFits` of a tall 2x2 face, then a large and a small one, and that view
/// picks the first face whose ideal size fits the tile: a face that is too big is never
/// chosen, and the widget would silently show only its disc in every size. The options page
/// has no such fallback and must simply fit the notch's interior.
@MainActor
@Suite("Caffeinate face fit")
struct CaffeinateFaceFitTests {

    /// The widget's tiles in the default notch: 400 points of interior width, a 2x2 tile 110
    /// points wide and 86 high, a 2x1 tile as wide and 40 high, and a 1x1 tile 52 by 40.
    private static let interior     = CGRect(x: 0, y: 0, width: 400, height: 124)
    private static let optionsFrame = CGSize(width: 400, height: 86)

    private static let owner = PluginID(rawValue: "com.cascade.caffeinate")!
    private static let key   = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)

    /// The states are built from the present moment, so the kernel-drawn time nodes show a
    /// plausible countdown: a session 36 minutes old with 24 minutes left.
    private static var states: [(name: String, state: PluginCaffeinateState)] {
        let now     = Date.now
        let started = now.addingTimeInterval(-36 * 60)

        return [
            ("off", PluginCaffeinateState()),
            ("off for", PluginCaffeinateState(nextTarget: .duration(minutes: 1_425))),
            ("off until", PluginCaffeinateState(nextTarget: .until(minuteOfDay: 22 * 60 + 45))),
            ("off indefinite", PluginCaffeinateState(nextTarget: .indefinite)),
            (
                "running until",
                PluginCaffeinateState(
                    startedAt        : started,
                    endsAt           : now.addingTimeInterval(5 * 3_600),
                    activityStartedAt: started,
                    nextTarget       : .until(minuteOfDay: 22 * 60 + 45)
                )
            ),
            (
                "timed",
                PluginCaffeinateState(
                    startedAt        : started,
                    endsAt           : now.addingTimeInterval(24 * 60),
                    activityStartedAt: started
                )
            ),
            (
                "indefinite",
                PluginCaffeinateState(
                    startedAt        : started,
                    activityStartedAt: started
                )
            ),
            ("refused start", PluginCaffeinateState(failure: .assertionRefused(-536_870_212))),
            (
                "refused extension",
                PluginCaffeinateState(
                    startedAt        : started,
                    endsAt           : now.addingTimeInterval(24 * 60),
                    activityStartedAt: started,
                    failure          : .extensionRefused(-536_870_212)
                )
            ),
        ]
    }

    @Test
    func eachFaceFitsTheTileItIsChosenFor() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == Self.owner })

        for (name, state) in Self.states {
            let document = try publish(state)
            #expect(document.root.kind == .viewThatFits(axes: .vertical), "\(name)")
            try #require(document.root.children.count == 2)
            let rest = document.root.children[1]
            #expect(rest.kind == .viewThatFits(axes: .horizontal), "\(name)")
            try #require(rest.children.count == 2)
            let faces = [document.root.children[0], rest.children[0], rest.children[1]]

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
            #expect(
                widget.sizes == [GridSpan(columns: 4, rows: 2), GridSpan(columns: 4, rows: 1), GridSpan(columns: 2, rows: 1)],
                "\(name)"
            )

            let tall       = try tile(widget.sizes[0], of: widget.id)
            let large      = try tile(widget.sizes[1], of: widget.id)
            let small      = try tile(widget.sizes[2], of: widget.id)
            let tallFace   = try idealSize(of: PluginDocument(root: faces[0]))
            let largeFace  = try idealSize(of: PluginDocument(root: faces[1]))
            let smallFace  = try idealSize(of: PluginDocument(root: faces[2]))

            // A measurement that came back empty would satisfy every upper bound below.
            #expect(tallFace.width > 60, "\(name): the 2x2 face measured \(tallFace.width) points wide")
            #expect(largeFace.width > 60, "\(name): the large face measured \(largeFace.width) points wide")
            #expect(smallFace.width > 10, "\(name): the small face measured \(smallFace.width) points wide")

            #expect(tallFace.width <= tall.width, "\(name): the 2x2 face is wider than its tile")
            #expect(tallFace.height <= tall.height, "\(name): the 2x2 face is taller than its tile")
            #expect(tallFace.height > large.height, "\(name): the 2x1 tile would show the 2x2 face")
            #expect(largeFace.width <= large.width, "\(name): the large face is wider than its 2x1 tile")
            #expect(largeFace.height <= large.height, "\(name): the large face is taller than its 2x1 tile")
            #expect(largeFace.width > small.width, "\(name): the 1x1 tile would show the large face")
            #expect(smallFace.width <= small.width, "\(name): the small face is wider than its 1x1 tile")
            #expect(smallFace.height <= small.height, "\(name): the small face is taller than its 1x1 tile")

            #expect(containsText(CaffeinateStyle.Copy.title, in: faces[0]), "\(name): the 2x2 tile shows no title")
            #expect(containsText(CaffeinateStyle.Copy.title, in: faces[1]), "\(name): the 2x1 tile shows no title")
            #expect(!containsText(CaffeinateStyle.Copy.title, in: faces[2]), "\(name): the 1x1 tile shows a title")
        }
    }

    @Test
    func theOptionsPageFitsTheExpandedNotchInEveryState() throws {
        for (name, state) in Self.states {
            let document = try publish(state)
            let options  = try #require(document.optionsRoot)
            let page     = try PluginDocument(root: options)

            let natural = try idealSize(of: page)
            #expect(natural.width > 200, "\(name): the options page measured \(natural.width) points wide")
            #expect(natural.height > 40, "\(name): the options page measured \(natural.height) points high")
            #expect(natural.width <= Self.optionsFrame.width, "\(name): the options page asks for \(natural.width) points of width")

            let fitted = try idealSize(of: page, width: Self.optionsFrame.width)
            #expect(fitted.height <= Self.optionsFrame.height, "\(name): the options page needs \(fitted.height) points of height")
        }
    }

    /// aRunningTimeAndItsEndLineFitTheBottomBand: the kernel's countdown is an AppKit label that
    /// an `ImageRenderer` does not draw, so its height is the line height of its font, and the
    /// end line under it is measured as the SwiftUI text it is. Together they must fit the 46
    /// points of the bottom band, in both widths of the clock (12 and 24 hours are one text
    /// in the locale the process runs in).
    @Test
    func aRunningTimeAndItsEndLineFitTheBottomBand() throws {
        let now     = Date.now
        let started = now.addingTimeInterval(-36 * 60)
        let running = PluginCaffeinateState(
            startedAt        : started,
            endsAt           : now.addingTimeInterval(5 * 3_600),
            activityStartedAt: started,
            nextTarget       : .until(minuteOfDay: 22 * 60 + 45)
        )
        let options = try #require(try publish(running).optionsRoot)

        func find(_ node: PluginNode) -> PluginNode? {
            if node.kind == .hStack(alignment: .center, spacing: 3), node.children.contains(where: { $0.kind == .text("until") }) {
                return node
            }

            return (node.children + node.layers).lazy.compactMap(find).first
        }

        let line     = try #require(find(options))
        let measured = try idealSize(of: PluginDocument(root: line))
        let font     = PluginFont.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit().nsFont
        let height   = ceil(font.ascender - font.descender + font.leading)

        #expect(measured.width > 20 && measured.width <= 124, "the end line measured \(measured.width) points wide")
        #expect(height + measured.height <= 46, "the countdown (\(height)) and its end line (\(measured.height)) need more than 46 points")
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
    ) throws -> CGSize {
        let store    = try nodeStore(document)
        let renderer = ImageRenderer(content: PluginDocumentView(store: store).environment(\.colorScheme, .dark))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale        = 1

        return try #require(renderer.nsImage).size
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
