//
//  AudioSpectrumStatus.swift
//  Cascade
//

/// AudioSpectrumStatus distinguishes unavailable capture from measured silence.
nonisolated enum AudioSpectrumStatus: Equatable, Sendable {

    case stopped
    case capturing
    case permissionRequired
    case unavailable(String)
}
