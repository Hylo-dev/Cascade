//
//  CalendarPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct CalendarPluginTests {

    private let context = PluginContext(plugin: CalendarPlugin.id)

    /// nodes lists a tree's nodes depth first, layers included, so a test can find one by what
    /// it carries.
    private func nodes(in node: PluginNode) -> [PluginNode] {
        [node] + (node.children + node.layers).flatMap { nodes(in: $0) }
    }

    private func face(
        at date : Date,
        calendar: Calendar
    ) throws -> PluginNode {
        try #require(try CalendarFace.publication(at: date, in: calendar).document).root
    }

    // MARK: - The month

    @Test
    func octoberStartsOnTheMondayBeforeItAndTakesFiveWeeks() throws {
        let rome  = try TestCalendar.rome(firstWeekday: 2)
        let month = CalendarMonth(containing: try TestCalendar.date(2026, 10, 2, 9, in: rome), calendar: rome)
        let days  = month.weeks.flatMap { $0 }

        #expect(month.title == "October 2026")
        #expect(month.weekdayInitials == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(month.weeks.count == 5)
        #expect(month.weeks.first?.map(\.number) == [28, 29, 30, 1, 2, 3, 4])
        #expect(month.weeks.last?.map(\.number) == [26, 27, 28, 29, 30, 31, 1])
        #expect(days.prefix(3).allSatisfy { !$0.isInMonth })
        #expect(days.last?.isInMonth == false)
        #expect(days.filter(\.isInMonth).map(\.number) == Array(1...31))
        #expect(days.filter(\.isToday).map(\.number) == [2])
        #expect(days.filter(\.isToday).allSatisfy { $0.isInMonth })
    }

    @Test
    func februaryTakesTheWeeksTheCalendarGivesIt() throws {
        let sundayFirst = try TestCalendar.rome(firstWeekday: 1)
        let mondayFirst = try TestCalendar.rome(firstWeekday: 2)
        let date        = try TestCalendar.date(2026, 2, 14, in: sundayFirst)

        let fromSunday = CalendarMonth(containing: date, calendar: sundayFirst)
        let fromMonday = CalendarMonth(containing: date, calendar: mondayFirst)

        #expect(fromSunday.weekdayInitials == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(fromSunday.weeks.count == 4)
        #expect(fromSunday.weeks.flatMap { $0 }.allSatisfy { $0.isInMonth })
        #expect(fromMonday.weeks.count == 5)
        #expect(fromMonday.weeks.first?.map(\.number) == [26, 27, 28, 29, 30, 31, 1])
    }

    @Test
    func aLeapFebruaryHasTwentyNineDays() throws {
        let rome  = try TestCalendar.rome(firstWeekday: 2)
        let month = CalendarMonth(containing: try TestCalendar.date(2028, 2, 29, 23, in: rome), calendar: rome)
        let days  = month.weeks.flatMap { $0 }

        #expect(days.filter(\.isInMonth).map(\.number) == Array(1...29))
        #expect(days.filter(\.isToday).map(\.number) == [29])
    }

    /// The months of 2026 start on every weekday, so laying each out from a Sunday and from a
    /// Monday covers a month starting on each weekday with either first weekday.
    @Test(arguments: [1, 2])
    func everyMonthIsWholeWeeksWithItsFirstDayUnderItsWeekday(firstWeekday: Int) throws {
        let rome = try TestCalendar.rome(firstWeekday: firstWeekday)

        for number in 1...12 {
            let first  = try TestCalendar.date(2026, number, 1, in: rome)
            let length = try #require(rome.range(of: .day, in: .month, for: first)).count
            let month  = CalendarMonth(containing: first, calendar: rome)
            let days   = month.weeks.flatMap { $0 }
            let column = (rome.component(.weekday, from: first) - firstWeekday + 7) % 7

            #expect((4...6).contains(month.weeks.count))
            #expect(month.weeks.allSatisfy { $0.count == 7 })
            #expect(days.firstIndex { $0.isInMonth } == column)
            #expect(days[column].number == 1)
            #expect(days.filter(\.isInMonth).map(\.number) == Array(1...length))
            #expect(days.count - column - length < 7)
        }
    }

    // MARK: - The face

    @Test
    func theMonthFaceHasTheTitleTheInitialsAndOneTextPerDay() throws {
        let rome  = try TestCalendar.rome(firstWeekday: 2)
        let date  = try TestCalendar.date(2026, 10, 2, 9, in: rome)
        let month = CalendarMonth(containing: date, calendar: rome)
        let large = try #require(try face(at: date, calendar: rome).children.first)
        let days  = month.weeks.flatMap { $0 }.map { day in "\(day.number)" }
        let texts = PluginNodeSearch.texts(in: large)

        #expect(texts.first == month.title)
        #expect(Array(texts.dropFirst().prefix(7)) == month.weekdayInitials)
        #expect(Array(texts.dropFirst(8)) == days)
    }

    @Test
    func todayIsCircledAndTheDaysAroundTheMonthAreDimmed() throws {
        let rome    = try TestCalendar.rome(firstWeekday: 2)
        let root    = try face(at: try TestCalendar.date(2026, 10, 2, 9, in: rome), calendar: rome)
        let large   = try #require(root.children.first)
        let circled = nodes(in: large).filter { $0.layers.contains { $0.kind == .shape(.circle) } }
        let dimmed  = nodes(in: large).filter { $0.modifiers.contains(.opacity(0.35)) }

        #expect(circled.map(\.kind) == [.text("2")])
        #expect(dimmed.map(\.kind) == [.text("28"), .text("29"), .text("30"), .text("1")])
    }

    /// Every initial and every day is a flexible column, so the seven share whatever width the
    /// tile has rather than adding up to exactly the width of one.
    @Test
    func theMonthSpreadsItsSevenColumnsAcrossTheTile() throws {
        let rome  = try TestCalendar.rome(firstWeekday: 2)
        let root  = try face(at: try TestCalendar.date(2026, 10, 2, 9, in: rome), calendar: rome)
        let large = try #require(root.children.first)
        let cells = large.children.dropFirst().flatMap(\.children)

        #expect(cells.count == 7 * 6)
        #expect(
            cells.allSatisfy { cell in
                cell.modifiers.contains { modifier in
                    if case .frame(nil, _, .infinity, _, _) = modifier { return true }

                    return false
                }
            }
        )
        #expect(
            !cells.contains { cell in
                cell.modifiers.contains { modifier in
                    if case .frame(.some, _, _, _, _) = modifier { return true }

                    return false
                }
            }
        )
    }

    @Test
    func theWeekdayInitialsAreSevenPointsAtThreeQuartersWhite() throws {
        let rome    = try TestCalendar.rome(firstWeekday: 2)
        let root    = try face(at: try TestCalendar.date(2026, 10, 2, 9, in: rome), calendar: rome)
        let header  = try #require(root.children.first?.children.dropFirst().first)
        let font    = PluginModifier.font(.system(size: 7, weight: .semibold, design: .rounded))
        let opacity = PluginModifier.foregroundStyle(.color(.white.opacity(0.75)))

        #expect(header.children.count == 7)
        #expect(header.children.allSatisfy { $0.modifiers.contains(font) && $0.modifiers.contains(opacity) })
    }

    @Test
    func theSmallFaceIsTheWeekdayAboveTheDay() throws {
        let rome  = try TestCalendar.rome(firstWeekday: 2)
        let root  = try face(at: try TestCalendar.date(2026, 10, 2, 9, in: rome), calendar: rome)
        let small = try #require(root.children.last)

        #expect(PluginNodeSearch.texts(in: small) == ["FRI", "2"])
        #expect(root.modifiers.contains(.accessibilityLabel("Friday, October 2, 2026")))
    }

    /// ViewThatFits measures a face with the tile's width already given, so a fixed height keeps
    /// the month for the tall tile and the day for the small one.
    @Test
    func theMonthIsChosenByTheTileHeight() throws {
        let rome  = try TestCalendar.rome()
        let root  = try face(at: try TestCalendar.date(2026, 10, 2, 9, in: rome), calendar: rome)
        let large = try #require(root.children.first)
        let fixed = PluginModifier.frame(
            width    : nil,
            height   : CalendarFace.largeHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .top
        )

        #expect(root.kind == .viewThatFits(axes: .vertical))
        #expect(root.children.count == 2)
        #expect(large.modifiers.contains(fixed))
    }

    @Test
    func aSixWeekMonthStaysWellUnderTheNodeLimit() throws {
        let rome = try TestCalendar.rome(firstWeekday: 2)
        let date = try TestCalendar.date(2026, 8, 31, in: rome)

        #expect(CalendarMonth(containing: date, calendar: rome).weeks.count == 6)
        #expect(PluginNodeSearch.kinds(in: try face(at: date, calendar: rome)).count < 80)
    }

    // MARK: - The plugin

    @Test
    func aRefreshPublishesTheWidgetAndAsksForTheNextMidnight() throws {
        let rome   = try TestCalendar.rome()
        let now    = try TestCalendar.date(2026, 10, 2, 9, in: rome)
        let plugin = CalendarPlugin(now: { now }, calendar: rome)

        let output      = try plugin.handle(.refresh, context: context)
        let publication = try #require(output.publications.first)

        #expect(output.publications.count == 1)
        #expect(publication.feature == CalendarPlugin.feature)
        #expect(publication.surface == .widget)
        #expect(publication == (try CalendarFace.publication(at: now, in: rome)))
        #expect(output.wake == nextMidnight(after: now, in: rome))
        #expect(output.wake == (try TestCalendar.date(2026, 10, 3, in: rome)))
    }

    /// A move to a zone ahead of this one starts the new day before the midnight the plugin waits
    /// for, so the publication goes stale after an hour and the first look after that refreshes it.
    @Test
    func thePublicationGoesStaleAfterAnHour() throws {
        let rome = try TestCalendar.rome()

        let publication = try CalendarFace.publication(at: try TestCalendar.date(2026, 10, 2, 9, in: rome), in: rome)

        #expect(publication.staleAfter == 3_600)
    }

    @Test
    func theMidnightWakeTurnsThePageAndAsksForTheNextOne() throws {
        let rome   = try TestCalendar.rome()
        let clock  = TestClock(try TestCalendar.date(2026, 10, 2, 23, 30, in: rome))
        let plugin = CalendarPlugin(now: { clock.now }, calendar: rome)
        _ = try plugin.handle(.refresh, context: context)

        clock.move(to: try TestCalendar.date(2026, 10, 3, 0, 0, in: rome).addingTimeInterval(1))
        let output   = try plugin.handle(.wake, context: context)
        let document = try #require(output.publications.first?.document)
        let small    = try #require(document.root.children.last)

        #expect(output.publications.count == 1)
        #expect(PluginNodeSearch.texts(in: small) == ["SAT", "3"])
        #expect(output.wake == (try TestCalendar.date(2026, 10, 4, in: rome)))
    }

    @Test
    func theManifestDeclaresTheSmallAndTheLargeTileAndNothingElse() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == CalendarPlugin.id })
        let feature  = try #require(manifest.features.first)
        let sizes    = [try PluginWidgetSize(columns: 1, rows: 1), try PluginWidgetSize(columns: 2, rows: 2)]

        #expect(manifest.execution.entryPoint == "CalendarPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == CalendarPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == sizes)
        #expect(feature.sources.isEmpty)
        #expect(feature.components.isEmpty)
        #expect(FirstPartyPlugins.name(of: CalendarPlugin.id) == "Calendar")
    }
}
