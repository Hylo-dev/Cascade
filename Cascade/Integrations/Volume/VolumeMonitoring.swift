//
//  VolumeMonitoring.swift
//  Cascade
//

/// VolumeMonitoringStatus tells the menu whether native volume keys can be
/// safely replaced. Every inactive state leaves macOS in charge of its HUD.
nonisolated enum VolumeMonitoringStatus: Equatable, Sendable {
    case stopped
    case starting
    case active
    case permissionRequired
    case unsupportedOutput
    case unavailable
}

/// VolumeMonitorUpdate transports copied state to the main actor. Its stream
/// coalesces volume changes; CoreAudio objects and callback pointers never cross.
nonisolated enum VolumeMonitorUpdate: Sendable {
    case status(VolumeMonitoringStatus)
    case changed(VolumeChangeEvent)
}

/// VolumeMonitoring owns listeners and a selective native-key replacement.
@MainActor
protocol VolumeMonitoring: AnyObject {
    func start() -> AsyncStream<VolumeMonitorUpdate>
    func stop()
    func refreshPermissions()
    func requestAccess()
}

/// SystemVolumeControlling hides synchronous CoreAudio access behind a worker
/// queue. A failed command must return false so the original key reaches macOS.
nonisolated protocol SystemVolumeControlling: AnyObject {
    var supportsVolume: Bool { get }
    func snapshot() -> SystemVolumeSnapshot?
    func perform(
        _ command: VolumeKeyCommand,
        fineStep : Bool
    ) -> Bool
}
