import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

struct PluginTimerScheduleTests {

    @Test
    func aVisibleTimerTicksAtSecondBoundariesThenStopsAtItsEnd() {
        let start = Date(timeIntervalSince1970: 0.25)
        let end = start.addingTimeInterval(2.5)
        let schedule = PluginTimerSchedule(start: start, end: end)
        let dates = Array(schedule.entries(from: start.addingTimeInterval(1.1), mode: .normal))

        #expect(dates == [start.addingTimeInterval(2), end])
        #expect(Array(schedule.entries(from: end.addingTimeInterval(1), mode: .normal)).isEmpty)
    }
}
