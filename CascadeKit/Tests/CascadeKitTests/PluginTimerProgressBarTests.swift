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

    /// drawn renders a document whose root is a timer progress over the last and the next
    /// minute, so its bar stands half full, 100 points wide.
    private func drawn(_ modifiers: [PluginModifier] = []) throws -> NSBitmapImageRep {
        let now       = Date.now
        let progress  = PluginNode(.timerProgress(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60)), modifiers: modifiers)
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: progress)))
        let renderer  = ImageRenderer(
            content: PluginDocumentView(store: store)
                .frame(width: 100)
        )
        renderer.scale = 1

        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
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
    /// that was there all along, and it stops at the end, where a finished bar has nothing left
    /// to draw.
    @Test
    func theScheduleStepsFromTheStartAndStopsAtTheEnd() {
        let end      = start.addingTimeInterval(50_000)
        let schedule = PluginTimerProgressBar.Schedule(start: start, end: end)

        let middle = Array(schedule.entries(from: start.addingTimeInterval(250), mode: .normal))
        let before = schedule.entries(from: start.addingTimeInterval(-150), mode: .normal).first { _ in true }
        let after  = Array(schedule.entries(from: end.addingTimeInterval(1_000), mode: .normal))

        #expect(middle.prefix(3) == [start.addingTimeInterval(200), start.addingTimeInterval(300), start.addingTimeInterval(400)])
        #expect(middle.last == end)
        #expect(middle.count == 499)
        #expect(before == start.addingTimeInterval(-200))
        #expect(after == [end])
    }

    @Test
    func aBarIsFivePointsTallAndNothingElse() throws {
        let progress  = PluginNode(.timerProgress(start: start, end: start.addingTimeInterval(60)))
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: progress)))

        let height = Double(NSHostingView(rootView: PluginDocumentView(store: store)).fittingSize.height)

        #expect(height == PluginTimerProgressBar.height)
    }

    @Test
    func aBarFillsInWhiteOverADimTrackByDefault() throws {
        let bitmap = try drawn()
        let filled = try color(in: bitmap, x: 20)
        let track  = try color(in: bitmap, x: 80)

        #expect(filled.alphaComponent > 0.9)
        #expect(filled.redComponent > 0.9 && filled.greenComponent > 0.9 && filled.blueComponent > 0.9)
        #expect(track.alphaComponent > 0.1 && track.alphaComponent < 0.4)
    }

    @Test
    func aBarFillsWithItsNodesForegroundStyle() throws {
        let red    = PluginColor(red: 1, green: 0, blue: 0)
        let bitmap = try drawn([.foregroundStyle(.color(red))])
        let filled = try color(in: bitmap, x: 20)

        #expect(filled.alphaComponent > 0.9)
        #expect(filled.redComponent > 0.9 && filled.greenComponent < 0.3 && filled.blueComponent < 0.3)
    }
}
