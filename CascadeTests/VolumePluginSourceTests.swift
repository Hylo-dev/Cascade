//
//  VolumePluginSourceTests.swift
//  CascadeTests
//

import CascadeContracts
import CascadePluginEngine
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

    /// A level the monitor did not announce, the first one of a session included, reaches the
    /// volume widget with the last counter, so the volume alerts show nothing for it.
    @Test
    func anUnannouncedLevelKeepsTheLastCounter() async throws {
        let monitor = FakeVolumeMonitor()
        let source  = VolumePluginSource(monitor: monitor)
        let emitted = Mutex<[PluginSourceEvent]>([])
        source.start { event in emitted.withLock { $0.append(event) } }
        try await waitUntil { emitted.withLock { $0.count } == 1 }

        monitor.send(.level(percentage: 30, isMuted: false))
        monitor.send(.changed(VolumeChangeEvent(percentage: 65, isMuted: false, revision: 1)))
        monitor.send(.level(percentage: 70, isMuted: true))
        try await waitUntil { emitted.withLock { $0.count } == 4 }

        let states = emitted.withLock { $0 }.compactMap(PluginVolumeState.init)
        #expect(states == [
            PluginVolumeState(percentage: nil, isMuted: false, announcement: 0),
            PluginVolumeState(percentage: 30, isMuted: false, announcement: 0),
            PluginVolumeState(percentage: 65, isMuted: false, announcement: 1),
            PluginVolumeState(percentage: 70, isMuted: true, announcement: 1),
        ])
    }

    /// The volume widget shares the source with the volume alerts, so the source may run while
    /// the alerts are off; the keys then leave macOS its own HUD, since nothing would replace it.
    @Test
    func theKeysReplaceTheSystemHUDOnlyWhileTheVolumeAlertsRun() {
        #expect(CascadeServices.routesVolumeKeys(alertsEnabled: true, alertsState: nil))
        #expect(CascadeServices.routesVolumeKeys(alertsEnabled: true, alertsState: .active))
        #expect(!CascadeServices.routesVolumeKeys(alertsEnabled: false, alertsState: .active))
        #expect(!CascadeServices.routesVolumeKeys(alertsEnabled: true, alertsState: .quarantined))
        #expect(!CascadeServices.routesVolumeKeys(alertsEnabled: true, alertsState: .disabledAfterHang))
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
