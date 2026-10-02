//
//  WorldClockFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// WorldClockFace is the world clock widget's document, a face for the tall 2x2 tile and one for
/// the short 2x1 tile, the taller first. The tall face lists the three cities, a row each: the
/// name in white with its day mark dimmed below it, and the time on the right. The short face
/// sets the first two cities side by side, each the name dimmed above the time with the mark
/// below. Every time is the kernel's clock in the city's zone, so the plugin never runs to turn
/// a minute; the mark, Tomorrow or Yesterday, is the plugin's, computed when it publishes.
///
/// The publication goes stale after an hour, as the calendar's does: the plugin waits for a
/// midnight reckoned in the zone the Mac was in, and a move to another zone shifts the local
/// day, so the first time the notch shows the widget an hour later the kernel asks for a
/// refresh.
///
/// Under a 38-point notch a 2x2 tile is 110 by 68 points and a 2x1 tile 110 by 31. A row of the
/// tall face is 22 points, so three fill its 66, and 102 wide: a 44-point name, a gap and a
/// 54-point time. The short face is two 51-point columns 6 apart, each three lines, about 30
/// points. Every name, mark and time has a fixed width that it shrinks into rather than spill
/// out of: New York, Yesterday and a 24-hour time fit theirs whole, and a twelve-hour time,
/// whose AM or PM the kernel adds in English, shrinks a little. The tall face is 66 points
/// tall: ViewThatFits measures a face with the tile's width already given, and a fixed height
/// keeps the choice on the tile.
enum WorldClockFace {

    static let largeHeight = 66.0

    private static let largePadding = 4.0
    private static let largeGap     = 4.0
    private static let nameWidth    = 44.0
    private static let timeWidth    = 54.0
    private static let columnWidth  = 51.0
    private static let columnGap    = 6.0

    static func publication(
        at date    : Date,
        in calendar: Calendar
    ) throws -> PluginPublication {
        let cities = WorldClockCity.all.map { city in
            (city, mark(for: city.dayOffset(at: date, local: calendar)))
        }

        return try PluginPublication(
            feature   : WorldClockPlugin.feature,
            surface   : .widget,
            document  : PluginDocument(
                root: ViewThatFits(in: .vertical) {

                    VStack(spacing: 0) {

                        for (city, mark) in cities {
                            row(city, mark: mark)
                        }
                    }
                    .padding(.horizontal, largePadding)
                    .frame(
                        height   : largeHeight,
                        maxWidth : .infinity,
                        maxHeight: .infinity
                    )

                    HStack(alignment: .top, spacing: columnGap) {

                        for (city, mark) in cities.prefix(2) {
                            column(city, mark: mark)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            ),
            staleAfter: 3_600
        )
    }

    /// row is one city of the tall face: the name above its mark, and the time on the right.
    private static func row(
        _ city: WorldClockCity,
        mark  : String?
    ) -> PluginNode {
        HStack(spacing: largeGap) {

            VStack(alignment: .leading, spacing: 0) {

                Text(city.name)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let mark {
                    markText(mark, size: 7.5)
                }
            }
            .frame(width: nameWidth, alignment: .leading)

            time(city, size: 13)
                .frame(width: timeWidth, alignment: .trailing)
        }
        .frame(height: largeHeight / Double(WorldClockCity.all.count))
    }

    /// column is one city of the short face: the name dimmed above the time, and the mark below.
    private static func column(
        _ city: WorldClockCity,
        mark  : String?
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: 0) {

            Text(city.name)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            time(city, size: 11.5)

            if let mark {
                markText(mark, size: 6.5)
            }
        }
        .frame(width: columnWidth, alignment: .leading)
    }

    /// time is the kernel's clock in the city's zone, rolling to the next minute.
    private static func time(
        _ city: WorldClockCity,
        size  : Double
    ) -> PluginNode {
        Clock()
            .timeZone(city.zone.identifier)
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText(countsDown: false))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// markText is a city's day mark, small and dimmed.
    private static func markText(
        _ mark: String,
        size  : Double
    ) -> PluginNode {
        Text(mark)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// mark is what a city's day is called beside the local one: tomorrow, yesterday, or nothing
    /// on the same day.
    private static func mark(for dayOffset: Int) -> String? {
        if dayOffset > 0 { return String(localized: "Tomorrow", table: "Plugins", bundle: .module) }
        if dayOffset < 0 { return String(localized: "Yesterday", table: "Plugins", bundle: .module) }

        return nil
    }
}
