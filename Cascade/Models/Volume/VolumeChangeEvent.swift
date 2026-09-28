//
//  VolumeChangeEvent.swift
//  Cascade
//



/// VolumeChangeEvent is the visible state of one real output-volume change.
nonisolated struct VolumeChangeEvent: Equatable, Sendable {
    let percentage: Int
    let isMuted   : Bool
    let revision  : UInt64
}
