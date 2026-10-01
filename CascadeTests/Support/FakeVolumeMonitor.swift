//
//  FakeVolumeMonitor.swift
//  CascadeTests
//

@testable import Cascade

/// FakeVolumeMonitor is a volume monitor the test plays: it hands out one stream and records
/// stops and permission requests.
@MainActor
final class FakeVolumeMonitor: VolumeMonitoring {

    private(set) var stops    = 0
    private(set) var requests = 0
    private var continuation : AsyncStream<VolumeMonitorUpdate>.Continuation?

    func start() -> AsyncStream<VolumeMonitorUpdate> {
        let (stream, continuation) = AsyncStream<VolumeMonitorUpdate>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() {
        stops += 1
        continuation?.finish()
        continuation = nil
    }

    func refreshPermissions() {}

    func requestAccess() {
        requests += 1
    }

    func send(_ update: VolumeMonitorUpdate) {
        continuation?.yield(update)
    }
}
