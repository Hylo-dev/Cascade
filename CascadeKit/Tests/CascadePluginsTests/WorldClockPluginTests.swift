//
//  WorldClockPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct WorldClockPluginTests {

    private let context = PluginContext(plugin: WorldClockPlugin.id)

    private func city(_ name: String) throws -> WorldClockCity {
        try #require(WorldClockCity.all.first { $0.name == name })
    }

    private func faces(
        at date : Date,
        calendar: Calendar
    ) throws -> (large: PluginNode, medium: PluginNode) {
        let root = try #require(try WorldClockFace.publication(at: date, in: calendar).document).root

        return (try #require(root.children.first), try #require(root.children.last))
    }

    /// zones lists the zone each kernel-drawn clock of a face is drawn in, in order.
    private func zones(in node: PluginNode) -> [String?] {
        PluginNodeSearch.nodes(in: node)
            .filter { $0.kind == .clock }
            .map { clock in
                clock.modifiers.lazy.compactMap { modifier in
                    if case .timeZone(let identifier) = modifier { return identifier }

                    return nil
                }
                .first
            }
    }

    // MARK: - The cities and their day

    @Test
    func theCitiesAreNewYorkLondonAndTokyoInTheirZones() throws {
        #expect(WorldClockCity.all.map(\.name) == ["New York", "London", "Tokyo"])
        #expect(WorldClockCity.all.map(\.zone.identifier) == ["America/New_York", "Europe/London", "Asia/Tokyo"])
        #expect(try ItalianStrings.value(of: "New York") == "New York")
        #expect(try ItalianStrings.value(of: "London") == "Londra")
        #expect(try ItalianStrings.value(of: "Tokyo") == "Tokyo")
    }

    @Test
    func lateInRomeTokyoIsAlreadyTomorrowAndNewYorkStillToday() throws {
        let rome = try TestCalendar.rome()
        let date = try TestCalendar.date(2026, 10, 2, 23, 30, in: rome)

        #expect(try city("Tokyo").dayOffset(at: date, local: rome) == 1)
        #expect(try city("London").dayOffset(at: date, local: rome) == 0)
        #expect(try city("New York").dayOffset(at: date, local: rome) == 0)
    }

    @Test
    func earlyInRomeNewYorkIsStillYesterday() throws {
        let rome = try TestCalendar.rome()
        let date = try TestCalendar.date(2026, 10, 2, 3, in: rome)

        #expect(try city("New York").dayOffset(at: date, local: rome) == -1)
        #expect(try city("London").dayOffset(at: date, local: rome) == 0)
        #expect(try city("Tokyo").dayOffset(at: date, local: rome) == 0)
    }

    // MARK: - The faces

    @Test
    func theLargeFaceShowsThreeCitiesAndTheMediumTwoEachWithItsZonesClock() throws {
        let rome  = try TestCalendar.rome()
        let faces = try faces(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), calendar: rome)

        #expect(PluginNodeSearch.texts(in: faces.large) == ["New York", "London", "Tokyo"])
        #expect(zones(in: faces.large) == ["America/New_York", "Europe/London", "Asia/Tokyo"])
        #expect(PluginNodeSearch.texts(in: faces.medium) == ["New York", "London"])
        #expect(zones(in: faces.medium) == ["America/New_York", "Europe/London"])
    }

    @Test
    func aCityAheadIsMarkedTomorrow() throws {
        let rome  = try TestCalendar.rome()
        let faces = try faces(at: try TestCalendar.date(2026, 10, 2, 23, 30, in: rome), calendar: rome)

        #expect(PluginNodeSearch.texts(in: faces.large) == ["New York", "London", "Tokyo", "Tomorrow"])
        #expect(PluginNodeSearch.texts(in: faces.medium) == ["New York", "London"])
        #expect(try ItalianStrings.value(of: "Tomorrow") == "Domani")
    }

    @Test
    func aCityBehindIsMarkedYesterday() throws {
        let rome  = try TestCalendar.rome()
        let faces = try faces(at: try TestCalendar.date(2026, 10, 2, 3, in: rome), calendar: rome)

        #expect(PluginNodeSearch.texts(in: faces.large) == ["New York", "Yesterday", "London", "Tokyo"])
        #expect(PluginNodeSearch.texts(in: faces.medium) == ["New York", "Yesterday", "London"])
        #expect(try ItalianStrings.value(of: "Yesterday") == "Ieri")
    }

    /// ViewThatFits measures a face with the tile's width already given, so the large face has a
    /// fixed height that a short tile cannot hold.
    @Test
    func theLargeFaceIsChosenByItsFixedHeight() throws {
        let rome     = try TestCalendar.rome()
        let document = try #require(try WorldClockFace.publication(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), in: rome).document)
        let large    = try #require(document.root.children.first)

        #expect(document.root.kind == .viewThatFits(axes: .vertical))
        #expect(document.root.children.count == 2)
        #expect(large.modifiers.contains { modifier in
            if case .frame(_, WorldClockFace.largeHeight?, _, _, _) = modifier { return true }

            return false
        })
    }

    /// A move to a zone ahead starts the new day before the midnight the plugin waits for, so the
    /// publication goes stale after an hour and the first look after that refreshes it.
    @Test
    func thePublicationGoesStaleAfterAnHour() throws {
        let rome = try TestCalendar.rome()

        #expect(try WorldClockFace.publication(at: try TestCalendar.date(2026, 10, 2, 12, in: rome), in: rome).staleAfter == 3_600)
    }

    // MARK: - The wake

    /// The earliest midnight to come is Tokyo's at noon in Rome, Rome's own in the evening,
    /// London's just after Rome's, and New York's in the small hours.
    @Test(
        arguments: [
            (12, 0, "Asia/Tokyo"),
            (20, 0, "Europe/Rome"),
            (23, 30, "Europe/Rome"),
            (0, 30, "Europe/London"),
            (3, 0, "America/New_York"),
        ]
    )
    func theWakeIsTheEarliestNextMidnightAmongTheLocalZoneAndTheCities(
        hour    : Int,
        minute  : Int,
        earliest: String
    ) throws {
        let rome   = try TestCalendar.rome()
        let now    = try TestCalendar.date(2026, 10, 2, hour, minute, in: rome)
        let plugin = WorldClockPlugin(now: { now }, calendar: rome)

        let output      = try plugin.handle(.refresh, context: context)
        let publication = try #require(output.publications.first)
        let midnight    = nextMidnight(after: now, in: try TestCalendar.calendar(in: earliest))

        #expect(output.publications.count == 1)
        #expect(publication.feature == WorldClockPlugin.feature)
        #expect(publication.surface == .widget)
        #expect(output.wake == midnight)
    }

    /// At Tokyo's midnight the wake marks Tokyo tomorrow and asks for the next midnight, Rome's.
    @Test
    func tokyosMidnightMarksItTomorrowAndWaitsForRomes() throws {
        let rome   = try TestCalendar.rome()
        let clock  = TestClock(try TestCalendar.date(2026, 10, 2, 16, 59, in: rome))
        let plugin = WorldClockPlugin(now: { clock.now }, calendar: rome)

        let before = try plugin.handle(.refresh, context: context)
        let wake   = try #require(before.wake)
        let large  = try #require(before.publications.first?.document?.root.children.first)

        #expect(wake == (try TestCalendar.date(2026, 10, 2, 17, in: rome)))
        #expect(PluginNodeSearch.texts(in: large) == ["New York", "London", "Tokyo"])

        clock.move(to: wake.addingTimeInterval(1))
        let after = try plugin.handle(.wake, context: context)
        let moved = try #require(after.publications.first?.document?.root.children.first)

        #expect(PluginNodeSearch.texts(in: moved) == ["New York", "London", "Tokyo", "Tomorrow"])
        #expect(after.wake == (try TestCalendar.date(2026, 10, 3, in: rome)))
    }

    // MARK: - The manifest

    @Test
    func theManifestDeclaresTheShortAndTheLargeTileAndNothingElse() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == WorldClockPlugin.id })
        let feature  = try #require(manifest.features.first)
        let sizes    = [try PluginWidgetSize(columns: 2, rows: 1), try PluginWidgetSize(columns: 2, rows: 2)]

        #expect(manifest.execution.entryPoint == "WorldClockPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == WorldClockPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == sizes)
        #expect(feature.sources.isEmpty)
        #expect(feature.components.isEmpty)
        #expect(!FirstPartyPlugins.placedByDefault.contains(WorldClockPlugin.id))
        #expect(FirstPartyPlugins.name(of: WorldClockPlugin.id) == "World clock")
        #expect(try ItalianStrings.value(of: "World clock") == "Orologio mondiale")
    }
}
