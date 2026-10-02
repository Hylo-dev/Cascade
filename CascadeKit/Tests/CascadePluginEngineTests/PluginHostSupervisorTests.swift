//
//  PluginHostSupervisorTests.swift
//  CascadeKit
//

import Testing

@testable import CascadePluginEngine

@Suite
struct PluginHostSupervisorTests {

    @Test
    func aKilledHostComesBackOnceItsLaunchIsTenSecondsOld() {
        var supervisor = PluginHostSupervisor()
        supervisor.launched(at: .zero)
        let young = supervisor.lost(.killed, at: .seconds(2))
        supervisor.launched(at: .seconds(100))
        let old = supervisor.lost(.killed, at: .seconds(200))

        #expect(young == .seconds(8))
        #expect(old == .zero)
    }

    @Test
    func aCrashedHostBacksOffOneFiveThenThirtySeconds() {
        var supervisor = PluginHostSupervisor()
        var delays: [Duration?] = []
        for second in [100, 200, 300, 350] {
            supervisor.launched(at: .seconds(second - 50))
            delays.append(supervisor.lost(.crashed, at: .seconds(second)))
        }

        #expect(delays == [.seconds(1), .seconds(5), .seconds(30), .seconds(30)])
    }

    @Test
    func theFloorWinsOverAShortBackoff() {
        var supervisor = PluginHostSupervisor()
        supervisor.launched(at: .zero)

        #expect(supervisor.lost(.crashed, at: .seconds(3)) == .seconds(7))
    }

    @Test
    func threeIdleCrashesInFiveMinutesGiveUp() {
        var supervisor = PluginHostSupervisor()
        var delays: [Duration?] = []
        for second in [100, 200, 300] {
            supervisor.launched(at: .seconds(second - 50))
            delays.append(supervisor.lost(.crashedIdle, at: .seconds(second)))
        }

        #expect(delays == [.seconds(1), .seconds(5), nil])
        #expect(supervisor.hasGivenUp)
    }

    @Test
    func idleCrashesOlderThanFiveMinutesAreForgotten() {
        var supervisor = PluginHostSupervisor()
        for second in [0, 200, 501] {
            supervisor.launched(at: .seconds(second - 50))
            _ = supervisor.lost(.crashedIdle, at: .seconds(second))
        }

        #expect(!supervisor.hasGivenUp)
    }
}
