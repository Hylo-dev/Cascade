//
//  SystemAudioControlling.swift
//  CascadeKit
//

/// SystemAudioControlling is how the model tells the system what the user chose. The app's audio
/// service implements it; the model depends on the contract, so tests drive it with a recorder.
///
/// Level and mute carry the HAL id of the device they were meant for, so a command that arrives
/// after the default output changed is the service's to drop, never to apply to the new device.
@MainActor
public protocol SystemAudioControlling: AnyObject {

    func setLevel(
        _ level: Double,
        forDevice deviceID: UInt32
    )

    func setMuted(
        _ isMuted: Bool,
        forDevice deviceID: UInt32
    )

    /// selectOutputs makes these outputs the system output: one uid is a plain default, several
    /// are a multi-output with the clock device first.
    func selectOutputs(_ uids: [String])
}
