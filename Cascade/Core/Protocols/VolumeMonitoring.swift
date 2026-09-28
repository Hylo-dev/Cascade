//
//  VolumeMonitoring.swift
//  Cascade
//

/// VolumeMonitoring owns listeners and a selective native-key replacement.
@MainActor
protocol VolumeMonitoring: AnyObject {

    func start() -> AsyncStream<VolumeMonitorUpdate>
    func stop()
    func refreshPermissions()
    func requestAccess()
}
