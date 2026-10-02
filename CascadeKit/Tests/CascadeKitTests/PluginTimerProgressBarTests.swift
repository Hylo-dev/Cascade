//
//  PluginTimerProgressBarTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginTimerProgressBarTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// halfway is a timer progress over the last and the next minute, so its bar stands half full.
    private func halfway(_ modifiers: [PluginModifier] = []) -> PluginNode {
        let now = Date.now

        return PluginNode(.timerProgress(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60)), modifiers: modifiers)
    }

    private func store(_ root: PluginNode) throws -> PluginNodeStore {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: root)))

        return store
    }

    /// widget renders a document as the notch's widget surface draws it, 100 points wide, in a
    /// light environment, so only the surface itself can make the defaults those of the black
    /// notch.
    private func widget(_ root: PluginNode) throws -> NSBitmapImageRep {
        let widget = PluginWidget(
            id               : WidgetIdentifier("test"),
            sizes            : [],
            isPlacedByDefault: false,
            store            : try store(root),
            visibility       : { _ in }
        )
        let renderer = ImageRenderer(
            content: widget.makeContentView()
                .frame(width: 100)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1

        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// drawn is what SwiftUI draws of a schedule asked at `date`: every entry but the last,
    /// which a finite timeline never draws, or the only entry when there is one.
    private func drawn(
        _ schedule: PluginTimerProgressBar.Schedule,
        from date : Date
    ) -> [Date] {
        let entries = Array(schedule.entries(from: date, mode: .normal))

        return entries.count > 1 ? Array(entries.dropLast()) : entries
    }

    private func color(
        in bitmap: NSBitmapImageRep,
        x        : Int
    ) throws -> NSColor {
        try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }

    @Test
    func aBarStepsAPixelOrLessOfAHundredAndTenPointBarAndNeverFasterThanASecond() {
        #expect(PluginTimerProgressBar.step(from: start, to: start.addingTimeInterval(86_400)) == 172.8)
        #expect(PluginTimerProgressBar.step(from: start, to: start.addingTimeInterval(300)) == 1)
        #expect(PluginTimerProgressBar.step(from: start, to: start) == 1)
    }

    @Test
    func theFractionClampsBeforeTheStartAndAfterTheEnd() {
        let end = start.addingTimeInterval(100)

        #expect(PluginTimerProgressBar.fraction(at: start.addingTimeInterval(-10), from: start, to: end) == 0)
        #expect(PluginTimerProgressBar.fraction(at: start.addingTimeInterval(25), from: start, to: end) == 0.25)
        #expect(PluginTimerProgressBar.fraction(at: end.addingTimeInterval(10), from: start, to: end) == 1)
        #expect(PluginTimerProgressBar.fraction(at: start.addingTimeInterval(-1), from: start, to: start) == 0)
        #expect(PluginTimerProgressBar.fraction(at: start, from: start, to: start) == 1)
    }

    /// The schedule steps on a grid from the start, so a bar that appears late lines up with one
    /// that was there all along.
    @Test
    func theScheduleStepsOnAGridFromTheStart() {
        let schedule = PluginTimerProgressBar.Schedule(start: start, end: start.addingTimeInterval(50_000))

        let drawn = drawn(schedule, from: start.addingTimeInterval(250))

        #expect(drawn.prefix(3) == [start.addingTimeInterval(200), start.addingTimeInterval(300), start.addingTimeInterval(400)])
    }

    /// SwiftUI never draws a finite timeline's last entry, so the entries go past the end and the
    /// last one drawn is at or after it: a bar of any length is drawn full once it ends, whether
    /// its end falls on the grid or between two steps.
    @Test(arguments: [8.0, 11.0, 50_000.0])
    func aBarIsDrawnFullOnceItEnds(span: Double) {
        let end      = start.addingTimeInterval(span)
        let schedule = PluginTimerProgressBar.Schedule(start: start, end: end)
        let step     = PluginTimerProgressBar.step(from: start, to: end)

        let last = drawn(schedule, from: start.addingTimeInterval(span / 2)).last ?? start

        #expect(last >= end)
        #expect(last < end.addingTimeInterval(2 * step))
        #expect(PluginTimerProgressBar.fraction(at: last, from: start, to: end) == 1)
    }

    /// A bar asked after its end has a single entry, which SwiftUI draws, full, and then the
    /// timeline has nothing left to wait for.
    @Test
    func aBarAskedAfterItsEndIsDrawnFullOnce() {
        let end      = start.addingTimeInterval(100)
        let schedule = PluginTimerProgressBar.Schedule(start: start, end: end)

        #expect(Array(schedule.entries(from: end.addingTimeInterval(1_000), mode: .normal)) == [end])
    }

    /// A bar that starts later is drawn once, empty, at once, since SwiftUI draws a first entry
    /// dated after now straight away, and then not again until it starts.
    @Test
    func aBarThatStartsLaterIsDrawnOnceUntilItStarts() {
        let schedule = PluginTimerProgressBar.Schedule(start: start, end: start.addingTimeInterval(50_000))

        let drawn = drawn(schedule, from: start.addingTimeInterval(-150))

        #expect(drawn.first == start)
        #expect(!drawn.contains { $0 < start })
    }

    @Test
    func aBarIsFivePointsTallAndNothingElse() throws {
        let progress  = PluginNode(.timerProgress(start: start, end: start.addingTimeInterval(60)))
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: progress)))

        let height = Double(NSHostingView(rootView: PluginDocumentView(store: store)).fittingSize.height)

        #expect(height == PluginProgressBar.height)
    }

    /// A linear progress is the same bar at a fixed fraction, so a paused timer looks like the
    /// running one rather than like SwiftUI's system bar, which turns grey in the notch's panel.
    @Test
    func aLinearProgressIsTheSameFivePointBar() throws {
        let progress = PluginNode(.progress(value: 0.5, total: 1, style: .linear))

        let height = Double(NSHostingView(rootView: PluginDocumentView(store: try store(progress))).fittingSize.height)

        #expect(height == PluginProgressBar.height)
    }

    @Test
    func aLinearProgressFillsToItsValueWithItsParentsForegroundStyle() throws {
        let red    = PluginColor(red: 1, green: 0, blue: 0)
        let parent = PluginNode(
            .vStack(alignment: .leading, spacing: nil),
            modifiers: [.foregroundStyle(.color(red))],
            children : [PluginNode(.progress(value: 1, total: 4, style: .linear))]
        )
        let bitmap = try widget(parent)
        let filled = try color(in: bitmap, x: 12)
        let track  = try color(in: bitmap, x: 60)

        #expect(filled.alphaComponent > 0.9)
        #expect(filled.redComponent > 0.9 && filled.greenComponent < 0.3 && filled.blueComponent < 0.3)
        #expect(track.alphaComponent > 0.1 && track.alphaComponent < 0.4)
    }

    /// A bar that inherits no style fills with the primary colour of the widget's dark scheme,
    /// the white of text that names no colour.
    @Test
    func aBarFillsInWhiteOverADimTrackByDefault() throws {
        let bitmap = try widget(halfway())
        let filled = try color(in: bitmap, x: 20)
        let track  = try color(in: bitmap, x: 80)

        #expect(filled.alphaComponent > 0.8)
        #expect(filled.redComponent > 0.9 && filled.greenComponent > 0.9 && filled.blueComponent > 0.9)
        #expect(track.alphaComponent > 0.1 && track.alphaComponent < 0.4)
    }

    @Test
    func aBarFillsWithItsNodesForegroundStyle() throws {
        let red    = PluginColor(red: 1, green: 0, blue: 0)
        let bitmap = try widget(halfway([.foregroundStyle(.color(red))]))
        let filled = try color(in: bitmap, x: 20)

        #expect(filled.alphaComponent > 0.9)
        #expect(filled.redComponent > 0.9 && filled.greenComponent < 0.3 && filled.blueComponent < 0.3)
    }

    /// A bar inherits a style its node does not name, as every other node does.
    @Test
    func aBarFillsWithItsParentsForegroundStyle() throws {
        let red    = PluginColor(red: 1, green: 0, blue: 0)
        let parent = PluginNode(
            .vStack(alignment: .leading, spacing: nil),
            modifiers: [.foregroundStyle(.color(red))],
            children : [halfway()]
        )
        let bitmap = try widget(parent)
        let filled = try color(in: bitmap, x: 20)

        #expect(filled.alphaComponent > 0.9)
        #expect(filled.redComponent > 0.9 && filled.greenComponent < 0.3 && filled.blueComponent < 0.3)
    }

    /// The widget surface draws in the dark scheme, as the notch's other surfaces do, so content
    /// that names no colour is white on the black notch whatever the system appearance.
    @Test
    func aWidgetDrawsTextThatNamesNoColourInWhite() throws {
        let bitmap = try widget(
            PluginNode(
                .text("████"),
                modifiers: [.font(PluginFont(size: 20, weight: nil, design: nil))]
            )
        )
        let ink = try (0..<bitmap.pixelsWide).map { x in try color(in: bitmap, x: x) }.filter { $0.alphaComponent > 0.5 }

        #expect(!ink.isEmpty)
        #expect(ink.allSatisfy { $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 })
    }
}
