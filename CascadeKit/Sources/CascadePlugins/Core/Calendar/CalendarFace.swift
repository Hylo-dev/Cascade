//
//  CalendarFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CalendarFace is the calendar widget's document, a face for each size, largest first, the
/// kernel showing the first that fits. The tall 2x2 tile is the month as a wall calendar sets
/// it: the month and year in red, the weekday initials dimmed, and a row per week with today
/// circled in red and the days of the months around it faded. The small 1x1 tile is the page
/// of a desk calendar: the weekday in red above the day. VoiceOver reads the whole date.
///
/// The publication goes stale after an hour. The midnight wake is reckoned in the zone the Mac
/// was in, and a move to a zone ahead, Rome to Tokyo, starts the new day hours before it; the
/// first time the notch shows the widget an hour or more after its last publication, the
/// kernel asks for a refresh, which costs one run when nothing changed.
///
/// Under a 38-point notch a 2x2 tile is 110 by 68 points and a 1x1 tile 52 by 31, and both faces
/// fit those. The month is 66 points tall, and every week takes an equal share of what the title
/// and the initials leave, with digits as tall as their row up to 8.5 points, so a month of 6
/// weeks fits as well as one of 4; the seven columns share the tile's width rather than adding
/// up to it, so another width spreads or narrows them and never clips one. The page is a 17-point
/// day under an 8.5-point weekday, 31 points together. The fixed height is also what chooses the
/// face: ViewThatFits measures a face with the tile's width already given, and a fixed height
/// keeps the choice on the tile, never on how far the text could shrink.
enum CalendarFace {

    static let largeHeight = 66.0

    private static let red          = PluginColor(red: 1, green: 0.27, blue: 0.23)
    private static let titleHeight  = 10.0
    private static let headerHeight = 9.0

    static func publication(
        at date    : Date,
        in calendar: Calendar
    ) throws -> PluginPublication {
        let style = CalendarMonth.style(in: calendar)

        return try PluginPublication(
            feature   : CalendarPlugin.feature,
            surface   : .widget,
            document  : PluginDocument(
                root: ViewThatFits(in: .vertical) {

                    month(CalendarMonth(containing: date, calendar: calendar))

                    page(
                        weekday: date.formatted(style.weekday(.abbreviated)).uppercased(with: style.locale),
                        day    : calendar.component(.day, from: date)
                    )
                }
                .accessibilityLabel(date.formatted(style.weekday(.wide).day().month(.wide).year()))
            ),
            staleAfter: 3_600
        )
    }

    /// month is the 2x2 face: the title, the initials and the weeks, each week an equal share
    /// of what the title and the initials leave.
    private static func month(_ month: CalendarMonth) -> PluginNode {
        let rowHeight = (largeHeight - titleHeight - headerHeight) / Double(max(month.weeks.count, 1))
        let digitSize = min(rowHeight, 8.5)

        return VStack(alignment: .leading, spacing: 0) {

            Text(month.title)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(red)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 3)
                .frame(height: titleHeight, alignment: .leading)

            HStack(spacing: 0) {

                for initial in month.weekdayInitials {
                    Text(initial)
                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(height: headerHeight, maxWidth: .infinity)
                }
            }

            for week in month.weeks {
                HStack(spacing: 0) {

                    for day in week {
                        number(
                            day,
                            size  : digitSize,
                            circle: min(rowHeight + 2, 13)
                        )
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .padding(.horizontal, 6)
        .frame(
            height   : largeHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
    }

    /// number is one day of the grid: white in the month, faded around it, and white on a red
    /// circle today.
    private static func number(
        _ day : CalendarMonth.Day,
        size  : Double,
        circle: Double
    ) -> PluginNode {
        let digits = Text("\(day.number)")
            .font(.system(size: size, weight: day.isToday ? .bold : .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)

        if day.isToday {
            return digits
                .background {
                    Circle()
                        .foregroundStyle(red)
                        .frame(width: circle, height: circle)
                }
                .frame(maxWidth: .infinity)
        }
        if !day.isInMonth {
            return digits
                .opacity(0.35)
                .frame(maxWidth: .infinity)
        }

        return digits
            .frame(maxWidth: .infinity)
    }

    /// page is the 1x1 face: the weekday in red above the day.
    private static func page(
        weekday: String,
        day    : Int
    ) -> PluginNode {
        VStack(spacing: 0) {

            Text(weekday)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(day)")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
