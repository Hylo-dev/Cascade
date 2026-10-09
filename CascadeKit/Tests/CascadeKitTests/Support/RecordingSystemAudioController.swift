//
//  RecordingSystemAudioController.swift
//  CascadeKit
//

@testable import CascadeKit

/// RecordingSystemAudioController keeps every command the model sends, in order, so a test can
/// read back what reached the system and for which device.
@MainActor
final class RecordingSystemAudioController: SystemAudioControlling {

    private(set) var levels       : [Double] = []
    private(set) var levelTargets : [UInt32] = []
    private(set) var mutes        : [Bool] = []
    private(set) var muteTargets  : [UInt32] = []
    private(set) var selections   : [[String]] = []

    func setLevel(
        _ level: Double,
        forDevice deviceID: UInt32
    ) {
        levels.append(level)
        levelTargets.append(deviceID)
    }

    func setMuted(
        _ isMuted: Bool,
        forDevice deviceID: UInt32
    ) {
        mutes.append(isMuted)
        muteTargets.append(deviceID)
    }

    func selectOutputs(_ uids: [String]) {
        selections.append(uids)
    }
}
