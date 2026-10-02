//
//  WorldClockPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// WorldClockPlugin is the world clock widget: the time in New York, London and Tokyo, each
/// marked when its day is not the local one. The kernel draws every time in its city's zone, so
/// a minute turning or a daylight-saving change costs the plugin nothing; what the plugin
/// decides is the day mark, which changes only at a midnight, local or in a city. It answers
/// every event with the face for now and a wake at the earliest of those midnights, on every
/// output because one without it would cancel it. It keeps no state, and its clock and calendar
/// are injected like the calendar widget's.
final class WorldClockPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.worldclock")!
    static let feature = "worldclock"

    private let now     : @Sendable () -> Date
    private let calendar: Calendar

    init(
        now     : @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.now      = now
        self.calendar = calendar
    }

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        let date      = now()
        let midnights = WorldClockCity.all.map { city in
            var cityCalendar = calendar
            cityCalendar.timeZone = city.zone

            return nextMidnight(after: date, in: cityCalendar)
        }

        return try PluginOutput(
            publications: [WorldClockFace.publication(at: date, in: calendar)],
            wake        : midnights.reduce(nextMidnight(after: date, in: calendar), min)
        )
    }
}
