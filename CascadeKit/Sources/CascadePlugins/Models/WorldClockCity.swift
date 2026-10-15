//
//  WorldClockCity.swift
//  CascadeKit
//

import Foundation

/// WorldClockCity is one city the world clock shows: its name in the user's language and its
/// zone. The list is fixed, New York, London and Tokyo, west to east, until plugin settings let
/// the user choose; a zone the system did not know would read as GMT, which none of these is.
struct WorldClockCity: Equatable, Sendable {

    static let all = [
        WorldClockCity(
            name: String(localized: "New York", table: "Plugins", bundle: .module),
            zone: TimeZone(identifier: "America/New_York") ?? .gmt
        ),
        WorldClockCity(
            name: String(localized: "London", table: "Plugins", bundle: .module),
            zone: TimeZone(identifier: "Europe/London") ?? .gmt
        ),
        WorldClockCity(
            name: String(localized: "Tokyo", table: "Plugins", bundle: .module),
            zone: TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        ),
    ]

    let name: String
    let zone: TimeZone

    /// dayOffset is the city's calendar day minus the local one at `date`: 1 when the city is
    /// already in tomorrow, -1 when it is still in yesterday, 0 on the same day. A wall clock
    /// reads the moment plus its zone's offset from GMT, and a day is the whole 86,400 seconds
    /// that wall time has counted since the reference date, a midnight in GMT, so comparing the
    /// two day numbers needs no calendar and holds across a daylight-saving change, whose offset
    /// is the one `secondsFromGMT(for:)` gives at that moment. Every zone on Earth is less than
    /// a day from New York, London and Tokyo, so the difference is never more than one either way.
    func dayOffset(
        at date: Date,
        local  : Calendar
    ) -> Int {
        func day(in zone: TimeZone) -> Double {
            ((date.timeIntervalSinceReferenceDate + Double(zone.secondsFromGMT(for: date))) / 86_400).rounded(.down)
        }

        return Int(day(in: zone) - day(in: local.timeZone))
    }
}
