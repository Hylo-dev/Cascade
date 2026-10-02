//
//  NetworkSourceTests.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Synchronization
import Testing

@testable import CascadePluginHost

/// NetworkSourceTests drive the `network` source with fake path monitors the test plays, so
/// nothing here reaches the Network framework.
@Suite
struct NetworkSourceTests {

    @Test
    func anUnsatisfiedPathIsOfflineWithNoInterface() {
        let offline = path(isSatisfied: false, usesWifi: true, isExpensive: true, isConstrained: true)

        #expect(offline.state == PluginNetworkState(isConnected: false, interface: .none, isExpensive: false, isConstrained: false))
    }

    @Test
    func wifiWinsOverCellularAndTheFlagsCarryOver() {
        let tethered = path(usesWifi: true, usesCellular: true, isExpensive: true, isConstrained: true)

        #expect(tethered.state == PluginNetworkState(isConnected: true, interface: .wifi, isExpensive: true, isConstrained: true))
    }

    @Test
    func theInterfaceFollowsWifiThenEthernetThenCellularThenOther() {
        #expect(path(usesWiredEthernet: true, usesCellular: true).state.interface == .ethernet)
        #expect(path(usesCellular: true).state.interface == .cellular)
        #expect(path().state.interface == .other)
    }

    @Test
    func anUnchangedPathEmitsNothingAndAChangedOneEmitsAgain() async throws {
        let monitors = FakePathMonitors()
        let source   = NetworkSource(monitor: monitors.make)
        let states   = Recorder<PluginNetworkState>()
        start(source, into: states)
        #expect(try await eventually { monitors.started.count == 1 })

        let monitor = monitors.started[0]
        monitor.deliver(path(usesWifi: true))
        monitor.deliver(path(usesWifi: true))
        monitor.deliver(path(usesWiredEthernet: true))
        source.stop()

        #expect(states.values.map(\.interface) == [.wifi, .ethernet])
    }

    @Test
    func stoppingCancelsTheMonitorAndStartingAgainStartsANewOne() async throws {
        let monitors = FakePathMonitors()
        let source   = NetworkSource(monitor: monitors.make)
        let states   = Recorder<PluginNetworkState>()
        start(source, into: states)
        #expect(try await eventually { monitors.started.count == 1 })

        let first = monitors.started[0]
        first.deliver(path(usesWifi: true))
        source.stop()
        #expect(try await eventually { first.isCancelled })
        first.deliver(path(usesCellular: true))

        start(source, into: states)
        #expect(try await eventually { monitors.started.count == 2 })
        monitors.started[1].deliver(path(usesWifi: true))
        first.deliver(path(usesCellular: true))
        source.stop()

        #expect(try await eventually { monitors.started[1].isCancelled })
        #expect(states.values.map(\.interface) == [.wifi, .wifi])
    }

    @Test
    func pluginHostOffersNetwork() {
        #expect(PluginHostCatalog.names.contains(PluginNetworkState.source))
    }

    private func start(
        _ source   : NetworkSource,
        into states: Recorder<PluginNetworkState>
    ) {
        source.start { event in
            if let state = PluginNetworkState(event) {
                states.record(state)
            }
        }
    }

    private func path(
        isSatisfied      : Bool = true,
        usesWifi         : Bool = false,
        usesWiredEthernet: Bool = false,
        usesCellular     : Bool = false,
        isExpensive      : Bool = false,
        isConstrained    : Bool = false
    ) -> NetworkPathSnapshot {
        NetworkPathSnapshot(
            isSatisfied      : isSatisfied,
            usesWifi         : usesWifi,
            usesWiredEthernet: usesWiredEthernet,
            usesCellular     : usesCellular,
            isExpensive      : isExpensive,
            isConstrained    : isConstrained
        )
    }
}

/// FakePathMonitors hands the source a new monitor each time it starts and keeps them in order.
/// The source builds a monitor a moment before it starts it, so a test waits on `started`, the
/// monitors that already have a queue to deliver on.
final class FakePathMonitors: Sendable {

    private let monitors = Mutex<[FakePathMonitor]>([])

    var started: [FakePathMonitor] {
        monitors.withLock { $0 }.filter(\.isStarted)
    }

    var make: @Sendable () -> any NetworkPathMonitoring {
        { [self] in
            let monitor = FakePathMonitor()
            monitors.withLock { $0.append(monitor) }
            return monitor
        }
    }
}

/// FakePathMonitor is one monitor the source started: `deliver` hands it a path on the queue it
/// was started on, as NWPathMonitor does, and keeps delivering after a cancel, as a block the
/// system had already queued would.
final class FakePathMonitor: NetworkPathMonitoring, Sendable {

    private let state = Mutex<(queue: DispatchQueue?, onUpdate: (@Sendable (NetworkPathSnapshot) -> Void)?, isCancelled: Bool)>((nil, nil, false))

    var isStarted: Bool {
        state.withLock { $0.queue != nil }
    }

    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    func start(
        queue   : DispatchQueue,
        onUpdate: @escaping @Sendable (NetworkPathSnapshot) -> Void
    ) {
        state.withLock { $0 = (queue, onUpdate, false) }
    }

    func cancel() {
        state.withLock { $0.isCancelled = true }
    }

    /// deliver records an issue instead of dropping the path when the monitor has not started.
    func deliver(_ snapshot: NetworkPathSnapshot) {
        let (queue, onUpdate) = state.withLock { ($0.queue, $0.onUpdate) }
        guard let queue, let onUpdate else {
            Issue.record("A path was delivered to a monitor the source has not started")
            return
        }

        queue.sync { onUpdate(snapshot) }
    }
}
