//
//  NetworkConnectionMonitor.swift
//  Cascade
//

import Foundation
import Network

/// NetworkConnectionMonitor observes Wi-Fi, Ethernet and other available paths
/// on a utility queue. Only copied connection state crosses into the main actor;
/// cancellation releases the native monitor and no polling wakes an idle app.
@MainActor
final class NetworkConnectionMonitor: NetworkMonitoring {
    private let queue = DispatchQueue(label: "Cascade.Network", qos: .utility)
    private var monitor: NWPathMonitor?
    private var continuation: AsyncStream<Bool>.Continuation?
    private var generation: UInt64 = 0

    /// start replaces a canceled monitor because NWPathMonitor cannot restart.
    /// Generation checks keep an old stream's termination from stopping its heir.
    func start() -> AsyncStream<Bool> {
        stop()
        let currentGeneration = generation
        let pair = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let continuation = pair.continuation
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            continuation.yield(path.status == .satisfied)
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.stop()
            }
        }
        self.monitor = monitor
        self.continuation = continuation
        monitor.start(queue: queue)
        return pair.stream
    }

    /// stop finishes consumers immediately; callbacks already queued can only
    /// yield into their finished stream and cannot affect a subsequent session.
    func stop() {
        generation &+= 1
        monitor?.cancel()
        monitor = nil
        continuation?.finish()
        continuation = nil
    }

    isolated deinit {
        monitor?.cancel()
        continuation?.finish()
    }
}
