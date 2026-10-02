//
//  ProgressFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// ProgressFace is the progress widget's document: how far today and this week have gone on the
/// short 2x1 tile, and this month and this year below them on the tall 2x2 tile, each a dimmed
/// label above a bar. The bars are the kernel's, drawn from a period's start and end, so they
/// fill on their own and the plugin runs only when a period ends, at a midnight.
///
/// Each bar is held to 5 points: the system bar is drawn that thin, but lays itself out 18
/// points tall, which would push two rows out of a 34-point tile. The large face is 66 points
/// tall, as the calendar's month is: ViewThatFits measures a face with the tile's width already
/// given, and a fixed height keeps the choice on the tile.
enum ProgressFace {

    static let largeHeight = 66.0

    private static let barHeight = 5.0

    static func publication(for periods: ProgressPeriods) throws -> PluginPublication {
        let day   = row(String(localized: "Today", table: "Plugins", bundle: .module), periods.day)
        let week  = row(String(localized: "This week", table: "Plugins", bundle: .module), periods.week)
        let month = row(String(localized: "This month", table: "Plugins", bundle: .module), periods.month)
        let year  = row(String(localized: "This year", table: "Plugins", bundle: .module), periods.year)

        return try PluginPublication(
            feature : ProgressPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .vertical) {

                    VStack(alignment: .leading, spacing: 1) {

                        day

                        week

                        month

                        year
                    }
                    .padding(.horizontal, 10)
                    .frame(
                        height   : largeHeight,
                        maxWidth : .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )

                    VStack(alignment: .leading, spacing: 2) {

                        day

                        week
                    }
                    .padding(.horizontal, 10)
                    .frame(
                        maxWidth : .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                }
            )
        )
    }

    /// row is one period: its name, small and dimmed, above the kernel's bar.
    private static func row(
        _ label : String,
        _ period: ClosedRange<Date>
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: 1) {

            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ProgressView(timerInterval: period)
                .frame(height: barHeight)
        }
    }
}
