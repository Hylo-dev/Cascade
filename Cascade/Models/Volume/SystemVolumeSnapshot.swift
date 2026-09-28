//
//  SystemVolumeSnapshot.swift
//  Cascade
//

/// SystemVolumeSnapshot carries copied CoreAudio values across isolation.
nonisolated struct SystemVolumeSnapshot: Equatable, Sendable {

    let deviceID: UInt32
    let scalar  : Double
    let isMuted : Bool
}
