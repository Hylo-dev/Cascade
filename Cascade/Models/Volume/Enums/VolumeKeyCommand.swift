//
//  VolumeKeyCommand.swift
//  Cascade
//



/// VolumeKeyCommand identifies only the three volume media keys.
nonisolated enum VolumeKeyCommand: Hashable, Sendable {
    case increase
    case decrease
    case toggleMute
}
