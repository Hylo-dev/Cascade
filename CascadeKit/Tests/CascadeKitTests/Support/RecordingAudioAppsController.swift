//
//  RecordingAudioAppsController.swift
//  CascadeKit
//

import CascadeContracts
@testable import CascadeKit

/// RecordingAudioAppsController keeps every per-app command the model sends, in order, so a test
/// can read back what would have reached the audio service.
@MainActor
final class RecordingAudioAppsController: AudioAppsControlling {

    private(set) var intents      : [AudioAppIntent] = []
    private(set) var intentTargets: [AudioAppIdentity] = []
    private(set) var returned     : [AudioAppIdentity] = []
    private(set) var visibility   : [Bool] = []

    func setIntent(
        _ intent: AudioAppIntent,
        for app : AudioAppIdentity
    ) {
        intents.append(intent)
        intentTargets.append(app)
    }

    func returnToNative(_ app: AudioAppIdentity) {
        returned.append(app)
    }

    func setMixerVisible(_ isVisible: Bool) {
        visibility.append(isVisible)
    }
}
