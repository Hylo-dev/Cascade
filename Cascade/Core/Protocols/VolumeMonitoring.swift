//
//  VolumeMonitoring.swift
//  Cascade
//

/// VolumeMonitoring owns listeners and a selective native-key replacement.
/// `routesKeys` says whether the key tap may replace the system HUD at all;
/// while it is false the monitor only observes the level and macOS keeps its
/// own HUD. It may change while the monitor runs.
@MainActor
protocol VolumeMonitoring: AnyObject {

    var routesKeys: Bool { get set }

    func start() -> AsyncStream<VolumeMonitorUpdate>
    func stop()
    func refreshPermissions()
    func requestAccess()
}
