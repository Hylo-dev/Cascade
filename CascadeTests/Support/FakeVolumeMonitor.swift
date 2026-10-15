//
//  FakeVolumeMonitor.swift
//  CascadeTests
//

@testable import Cascade

/// FakeVolumeMonitor is a volume monitor the test plays: it hands out one stream, which keeps
/// only its newest updates as the real monitor's does, and records starts, stops and permission
/// requests.
@MainActor
final class FakeVolumeMonitor: VolumeMonitoring {

    static let bufferedUpdates = 8

    var routesKeys = true

    private(set) var starts   = 0
    private(set) var stops    = 0
    private(set) var requests = 0
    private var continuation : AsyncStream<VolumeMonitorUpdate>.Continuation?

    func start() -> AsyncStream<VolumeMonitorUpdate> {
        starts += 1
        let (stream, continuation) = AsyncStream<VolumeMonitorUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.bufferedUpdates)
        )
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
