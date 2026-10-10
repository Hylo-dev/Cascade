//
//  SystemAudioHardware.swift
//  Cascade
//

import CascadeKit

/// SystemAudioHardware is the audio system as the volume bar's service sees it: the output
/// devices, the default output, its level and mute, and the listeners that say something changed.
/// It is a protocol so the service is tested against a fake, with no sound card.
///
/// Every call is synchronous and happens on the service's serial queue, never on the main
/// thread: the HAL can block. A conformer is therefore `nonisolated`, and so are the listener
/// blocks it registers, or a main-actor callback running on that queue would trap.
nonisolated protocol SystemAudioHardware: AnyObject, Sendable {

    /// outputDevices lists every device with output streams. The Bluetooth identity is nil; the
    /// service fills it in.
    func outputDevices() -> [AudioOutputDevice]

    func defaultOutput() -> (deviceID: UInt32, uid: String)?

    /// volume reads the level and mute of the default output, or nil when `deviceID` is not it.
    /// A default output with no volume control answers `supportsVolume` false.
    func volume(of deviceID: UInt32) -> (level: Double, isMuted: Bool, supportsVolume: Bool)?

    func setVolume(
        _ level    : Double,
        of deviceID: UInt32
    ) -> Bool

    func setMuted(
        _ isMuted  : Bool,
        of deviceID: UInt32
    ) -> Bool

    func setDefaultOutput(uid: String) -> Bool

    /// subDeviceUIDs lists the members of an aggregate output in order, or nil when the uid is
    /// not an aggregate.
    func subDeviceUIDs(ofAggregate uid: String) -> [String]?

    /// listen calls `onChange` on the service's queue when the devices, the default output, or
    /// the level or mute of the default output change. A second call replaces the first.
    func listen(_ onChange: @escaping @Sendable () -> Void)

    func stopListening()
}
