//
//  VolumeMonitorUpdate.swift
//  Cascade
//

/// VolumeMonitorUpdate transports copied state to the main actor. Its stream
/// coalesces volume changes; CoreAudio objects and callback pointers never cross.
nonisolated enum VolumeMonitorUpdate: Sendable {

    case status (VolumeMonitoringStatus)
    case changed(VolumeChangeEvent)
}
