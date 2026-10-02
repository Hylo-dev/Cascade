//
//  VolumePluginSourceTests.swift
//  CascadeTests
//

import CascadeContracts
import Foundation
import Synchronization
import Testing
@testable import Cascade

@MainActor
struct VolumePluginSourceTests {

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test
    func startingEmitsABaselineThenEveryAnnouncedChange() async throws {
        let monitor = FakeVolumeMonitor()
        let source  = VolumePluginSource(monitor: monitor)
        let emitted = Mutex<[PluginSourceEvent]>([])
        source.start { event in emitted.withLock { $0.append(event) } }
        try await waitUntil { emitted.withLock { $0.count } == 1 }

        monitor.send(.changed(VolumeChangeEvent(percentage: 65, isMuted: false, revision: 1)))
        try await waitUntil { emitted.withLock { $0.count } == 2 }

        let states = emitted.withLock { $0 }.compactMap(PluginVolumeState.init)
        #expect(states == [
            PluginVolumeState(percentage: nil, isMuted: false, announcement: 0),
            PluginVolumeState(percentage: 65, isMuted: false, announcement: 1),
        ])
    }

    @Test
    func everyAnnouncedChangeMovesTheCounterEvenAtTheSameLevel() async throws {
        let monitor = FakeVolumeMonitor()
        let source  = VolumePluginSource(monitor: monitor)
        let emitted = Mutex<[PluginSourceEvent]>([])
        source.start { event in emitted.withLock { $0.append(event) } }
        try await waitUntil { emitted.withLock { $0.count } == 1 }

        monitor.send(.changed(VolumeChangeEvent(percentage: 100, isMuted: false, revision: 1)))
        monitor.send(.changed(VolumeChangeEvent(percentage: 100, isMuted: false, revision: 2)))
        try await waitUntil { emitted.withLock { $0.count } == 3 }

        let counters = emitted.withLock { $0 }.compactMap(PluginVolumeState.init).map(\.announcement)
        #expect(counters == [0, 1, 2])
    }

    @Test
    func stoppingTheSourceStopsTheMonitor() async throws {
        let monitor = FakeVolumeMonitor()
        let source  = VolumePluginSource(monitor: monitor)
        source.start { _ in }

        source.stop()
        try await waitUntil { monitor.stops == 1 }

        #expect(monitor.stops == 1)
    }

    @Test
    func theMonitorsStatusReachesItsHandler() async throws {
        let monitor  = FakeVolumeMonitor()
        let source   = VolumePluginSource(monitor: monitor)
        var statuses: [VolumeMonitoringStatus] = []
        source.statusHandler = { statuses.append($0) }
        source.start { _ in }
        try await waitUntil { statuses.contains(.starting) }

        monitor.send(.status(.active))
        try await waitUntil { statuses.contains(.active) }
        source.stop()
        try await waitUntil { statuses.last == .stopped }

        #expect(statuses == [.starting, .active, .stopped])
    }
}
