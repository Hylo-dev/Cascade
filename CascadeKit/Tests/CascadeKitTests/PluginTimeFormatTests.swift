//
//  PluginTimeFormatTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeKit

/// PluginTimeFormatTests pins down the kernel's clock and today in a named zone, whatever the Mac's:
/// half past eleven at night in UTC is the next morning in Tokyo and past midnight in Rome, so
/// both the hour and the day move with the zone.
struct PluginTimeFormatTests {

    private let date   = Date(timeIntervalSince1970: 1_790_983_800) // 2026-10-02T23:30:00Z
    private let locale = Locale(identifier: "en_GB")

    @Test
    func theClockReadsTheTimeInTheGivenZone() throws {
        #expect(PluginTimeFormat.clock(date, in: try #require(TimeZone(identifier: "Asia/Tokyo")), locale: locale) == "08:30")
        #expect(PluginTimeFormat.clock(date, in: try #require(TimeZone(identifier: "Europe/Rome")), locale: locale) == "01:30")
    }

    @Test
    func todayReadsTheDayInTheGivenZone() throws {
        #expect(PluginTimeFormat.today(date, in: try #require(TimeZone(identifier: "Asia/Tokyo")), locale: locale) == "Sat 3 Oct")
        #expect(PluginTimeFormat.today(date, in: try #require(TimeZone(identifier: "Europe/Rome")), locale: locale) == "Sat 3 Oct")
    }
}
