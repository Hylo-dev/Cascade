//
//  ProgressPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct ProgressPluginTests {

    private let context = PluginContext(plugin: ProgressPlugin.id)

    /// bars lists the kernel-drawn bars of a face, in order.
    private func bars(in node: PluginNode) -> [PluginNodeKind] {
        PluginNodeSearch.kinds(in: node).filter { kind in
            if case .timerProgress = kind { return true }

            return false
        }
    }

    private func bar(_ period: ClosedRange<Date>) -> PluginNodeKind {
        .timerProgress(start: period.lowerBound, end: period.upperBound)
    }

    /// midnights is the period from the start of one day to the start of another.
    private func midnights(
        _ start    : (year: Int, month: Int, day: Int),
        _ end      : (year: Int, month: Int, day: Int),
        in calendar: Calendar
    ) throws -> ClosedRange<Date> {
        let from = try TestCalendar.date(start.year, start.month, start.day, in: calendar)
        let to   = try TestCalendar.date(end.year, end.month, end.day, in: calendar)

        return from...to
    }

    // MARK: - The periods

    @Test
    func thePeriodsAreTheDayTheWeekTheMonthAndTheYearAroundTheMoment() throws {
        let rome    = try TestCalendar.rome(firstWeekday: 2)
        let periods = ProgressPeriods(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), calendar: rome)

        #expect(periods.day == (try midnights((2026, 10, 2), (2026, 10, 3), in: rome)))
        #expect(periods.week == (try midnights((2026, 9, 28), (2026, 10, 5), in: rome)))
        #expect(periods.month == (try midnights((2026, 10, 1), (2026, 11, 1), in: rome)))
        #expect(periods.year == (try midnights((2026, 1, 1), (2027, 1, 1), in: rome)))
    }

    @Test
    func theWeekStartsOnTheCalendarsFirstWeekday() throws {
        let rome    = try TestCalendar.rome(firstWeekday: 1)
        let periods = ProgressPeriods(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), calendar: rome)

        #expect(periods.week == (try midnights((2026, 9, 27), (2026, 10, 4), in: rome)))
    }

    @Test
    func aDayThatGainsAnHourLastsTwentyFiveHours() throws {
        let rome = try TestCalendar.rome()
        let noon = try TestCalendar.date(2026, 10, 25, 12, in: rome)
        let day  = ProgressPeriods(at: noon, calendar: rome).day

        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 25 * 3_600)
    }

    // MARK: - The face and the plugin

    @Test
    func aRefreshPublishesFourBarsOnTheLargeTileTwoOnTheShortOneAndAsksForMidnight() throws {
        let rome    = try TestCalendar.rome()
        let now     = try TestCalendar.date(2026, 10, 2, 12, in: rome)
        let periods = ProgressPeriods(at: now, calendar: rome)
        let plugin  = ProgressPlugin(now: { now }, calendar: rome)

        let output      = try plugin.handle(.refresh, context: context)
        let publication = try #require(output.publications.first)
        let root        = try #require(publication.document).root
        let large       = try #require(root.children.first)
        let medium      = try #require(root.children.last)

        #expect(output.publications.count == 1)
        #expect(publication.feature == ProgressPlugin.feature)
        #expect(publication.surface == .widget)
        #expect(bars(in: large) == [bar(periods.day), bar(periods.week), bar(periods.month), bar(periods.year)])
        #expect(bars(in: medium) == [bar(periods.day), bar(periods.week)])
        #expect(PluginNodeSearch.texts(in: large) == ["Today", "This week", "This month", "This year"])
        #expect(PluginNodeSearch.texts(in: medium) == ["Today", "This week"])
        #expect(output.wake == nextMidnight(after: now, in: rome))
    }

    /// A move to a zone ahead of this one starts the new day before the midnight the plugin waits
    /// for, so the publication goes stale after an hour and the first look after that refreshes it.
    @Test
    func thePublicationGoesStaleAfterAnHour() throws {
        let rome    = try TestCalendar.rome()
        let periods = ProgressPeriods(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), calendar: rome)

        #expect(try ProgressFace.publication(for: periods).staleAfter == 3_600)
    }

    @Test
    func theMidnightWakeStartsTheNewWeekAndAsksForTheNextMidnight() throws {
        let rome   = try TestCalendar.rome(firstWeekday: 2)
        let clock  = TestClock(try TestCalendar.date(2026, 10, 4, 23, in: rome))
        let plugin = ProgressPlugin(now: { clock.now }, calendar: rome)
        _ = try plugin.handle(.refresh, context: context)

        clock.move(to: try TestCalendar.date(2026, 10, 5, in: rome).addingTimeInterval(1))
        let output   = try plugin.handle(.wake, context: context)
        let document = try #require(output.publications.first?.document)
        let medium   = try #require(document.root.children.last)
        let week     = try midnights((2026, 10, 5), (2026, 10, 12), in: rome)

        #expect(bars(in: medium).last == bar(week))
        #expect(output.wake == (try TestCalendar.date(2026, 10, 6, in: rome)))
    }

    /// The bars are white, as the clock's and the battery's figures are, rather than the dimmer
    /// primary colour a bar that names no style inherits.
    @Test
    func theBarsAreWhite() throws {
        let rome     = try TestCalendar.rome()
        let periods  = ProgressPeriods(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), calendar: rome)
        let document = try #require(try ProgressFace.publication(for: periods).document)
        let bars     = PluginNodeSearch.nodes(in: document.root).filter { node in
            if case .timerProgress = node.kind { return true }

            return false
        }

        #expect(bars.count == 6)
        #expect(bars.allSatisfy { $0.modifiers == [.foregroundStyle(.color(.white))] })
    }

    /// ViewThatFits measures a face with the tile's width already given, so a fixed height keeps
    /// the four bars for the tall tile and two for the short one.
    @Test
    func theFourBarsAreChosenByTheTileHeight() throws {
        let rome     = try TestCalendar.rome()
        let periods  = ProgressPeriods(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), calendar: rome)
        let document = try #require(try ProgressFace.publication(for: periods).document)
        let large    = try #require(document.root.children.first)
        let fixed    = PluginModifier.frame(
            width    : nil,
            height   : ProgressFace.largeHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )

        #expect(document.root.kind == .viewThatFits(axes: .vertical))
        #expect(document.root.children.count == 2)
        #expect(large.modifiers.contains(fixed))
    }

    @Test
    func theManifestDeclaresTheShortAndTheLargeTileAndNothingElse() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == ProgressPlugin.id })
        let feature  = try #require(manifest.features.first)
        let sizes    = [try PluginWidgetSize(columns: 2, rows: 1), try PluginWidgetSize(columns: 2, rows: 2)]

        #expect(manifest.execution.entryPoint == "ProgressPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == ProgressPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == sizes)
        #expect(feature.sources.isEmpty)
        #expect(feature.components.isEmpty)
        #expect(FirstPartyPlugins.name(of: ProgressPlugin.id) == "Progress")
    }
}
