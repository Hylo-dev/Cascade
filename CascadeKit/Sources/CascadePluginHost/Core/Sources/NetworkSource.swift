//
//  NetworkSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Network

/// NetworkSource is the `network` catalog source: whether the Mac is online, through which kind
/// of link, and whether that link is expensive or constrained, emitted only when one of them
/// changes. It never polls and opens no connection: an `NWPathMonitor` reports the path on the
/// source's own utility queue, at once when it starts and then only when the path changes. A
/// monitor cannot start again once cancelled, so every start builds a new one.
///
/// Every stored property below is read and written only on `queue`, which is what makes the type
/// safe to share; `start` and `stop` reach it with `queue.async` from the XPC threads, so they
/// never wait on the monitor's callback. Each start numbers its session and the monitor's
/// handler carries that number, so an update a cancelled monitor had already queued is dropped
/// instead of overwriting a newer start's state.
public final class NetworkSource: PluginCatalogSource, @unchecked Sendable {

    private let queue      = DispatchQueue(label: "cascade.plugin-host.network", qos: .utility)
    private let makeMonitor: @Sendable () -> any NetworkPathMonitoring

    private var monitor  : (any NetworkPathMonitoring)?
    private var emit     : (@Sendable (PluginSourceEvent) -> Void)?
    private var last     : PluginNetworkState?
    private var sessionID = UInt64.zero

    public convenience init() {
        self.init(monitor: { NWPathMonitor() })
    }

    init(monitor: @escaping @Sendable () -> any NetworkPathMonitoring) {
        self.makeMonitor = monitor
    }

    public func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        queue.async { [self] in
            tearDown()

            sessionID &+= 1
            let session = sessionID
            let monitor = makeMonitor()
            self.emit    = emit
            self.monitor = monitor

            monitor.start(queue: queue) { [weak self] snapshot in
                self?.receive(snapshot, session: session)
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            tearDown()
        }
    }

    private func receive(
        _ snapshot: NetworkPathSnapshot,
        session   : UInt64
    ) {
        guard session == sessionID, let emit else { return }

        let state = snapshot.state
        guard state != last, let event = try? state.event() else { return }

        last = state
        emit(event)
    }

    private func tearDown() {
        monitor?.cancel()
        monitor = nil
        emit    = nil
        last    = nil
    }
}
