//
//  VolumeMonitoringStatus.swift
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
