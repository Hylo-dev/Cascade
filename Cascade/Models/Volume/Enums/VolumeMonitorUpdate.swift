//
//  VolumeMonitorUpdate.swift
//  Cascade
//

/// VolumeMonitorUpdate transports copied state to the main actor. Its stream
/// coalesces volume changes; CoreAudio objects and callback pointers never cross.
/// A change worth a notice is `changed`; any other change of the visible level,
/// the first of a session included, is `level`, for what shows the level
/// without announcing it. A level carries the last announcement's revision, so
/// whichever update a full stream keeps carries the newest one.
nonisolated enum VolumeMonitorUpdate: Sendable {

    case status (VolumeMonitoringStatus)
    case changed(VolumeChangeEvent)
    case level  (VolumeChangeEvent)
}
