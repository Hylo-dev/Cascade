//
//  FirstPartyWidgetFitTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine
@testable import CascadePlugins

/// FirstPartyWidgetFitTests draws each face of the first-party widgets with the kernel's own
/// renderer and holds it to the smallest tile of its size. Under a 38-point notch the grid's
/// main rows are 31 points tall, so a 1x1 tile is 52 by 31, a 2x1 tile 110 by 31 and a 2x2 tile
/// 110 by 68; a face whose natural size is larger would spill over the tile beside it.
@MainActor
struct FirstPartyWidgetFitTests {

    private static let small = CGSize(width: 52, height: 31)
    private static let short = CGSize(width: 110, height: 31)
    private static let large = CGSize(width: 110, height: 68)

    /// size is what a face asks for when nothing constrains it, drawn alone as a document.
    private func size(of face: PluginNode) throws -> CGSize {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: face)))

        return NSHostingView(rootView: PluginDocumentView(store: store)).fittingSize
    }

    private func faces(of publication: PluginPublication) throws -> [PluginNode] {
        try #require(publication.document).root.children
    }

    /// fits holds a face to the tile twice: as drawn, and without its own frames, so content
    /// that a fixed frame would hide, spilling past it, counts too.
    private func fits(
        _ face : PluginNode,
        in tile: CGSize
    ) throws -> Bool {
        let unframed = PluginNode(
            face.kind,
            id       : face.id,
            modifiers: face.modifiers.filter { modifier in
                if case .frame = modifier { return false }

                return true
            },
            children : face.children,
            layers   : face.layers
        )

        return try [size(of: face), size(of: unframed)].allSatisfy { size in
            size.width <= tile.width && size.height <= tile.height
        }
    }

    @Test(arguments: [(2026, 2, 14), (2026, 8, 31), (2026, 10, 2)])
    func everyCalendarFaceFitsItsTile(
        year : Int,
        month: Int,
        day  : Int
    ) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale       = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        let date  = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9)))
        let faces = try faces(of: CalendarFace.publication(at: date, in: calendar))

        #expect(try fits(faces[0], in: Self.large))
        #expect(try fits(faces[1], in: Self.small))
    }

    @Test
    func everyProgressFaceFitsItsTile() throws {
        let faces = try faces(of: ProgressFace.publication(for: ProgressPeriods(at: Date.now, calendar: .autoupdatingCurrent)))

        #expect(try fits(faces[0], in: Self.large))
        #expect(try fits(faces[1], in: Self.short))
    }

    /// Every state of the timer, with the most buttons or the longest time it can show.
    @Test
    func everyTimerFaceFitsItsTile() throws {
        let longest = TimerState.longestDuration
        let states: [TimerState] = [
            .idle(duration: 0),
            .idle(duration: 300),
            .idle(duration: longest),
            .running(end: Date.now.addingTimeInterval(longest), duration: longest),
            .paused(remaining: longest, duration: longest),
        ]

        for state in states {
            let faces   = try faces(of: TimerFace.publication(for: state))
            let smaller = faces[1].children

            #expect(try fits(faces[0], in: Self.large))
            #expect(try fits(smaller[0], in: Self.short))
            #expect(try fits(smaller[1], in: Self.small))
        }
    }

    @Test
    func everyStopwatchFaceFitsItsTile() throws {
        let states: [StopwatchState] = [
            .idle,
            .running(since: Date.now, before: 3_725),
            .paused(elapsed: 3_725),
        ]

        for state in states {
            let faces = try faces(of: StopwatchFace.publication(for: state))

            #expect(try fits(faces[0], in: Self.short))
            #expect(try fits(faces[1], in: Self.small))
        }
    }
}
