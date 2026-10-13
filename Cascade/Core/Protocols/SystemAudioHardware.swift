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

    /// createMultiOutput builds a public, stacked aggregate over the given outputs, in order, and
    /// returns its uid (`cascade.multi-output.<uuid>`), or nil when the HAL refuses. The first
    /// member is the aggregate's main and clock device. It does not make the aggregate the
    /// default output: that is a separate step, so the caller decides the order.
    func createMultiOutput(subDeviceUIDs: [String]) -> String?

    /// destroyAggregate removes an aggregate for good. The answer is whether the HAL did.
    func destroyAggregate(uid: String) -> Bool

    /// aggregateUIDs lists the uid of every aggregate device whose uid starts with the prefix,
    /// output streams or not. A public aggregate outlives a killed Cascade, so this is how the
    /// next launch finds what was left behind.
    func aggregateUIDs(withPrefix prefix: String) -> [String]

    /// listen starts the two kinds of change the service cares about, on the service's queue.
    /// `onDevicesChange` is the device list or the default output changing; it costs the service
    /// a full enumeration. `onVolumeChange` is the level or mute of the default output, which
    /// can fire dozens of times a second during a drag, and costs the service two small reads.
    /// A second call replaces the first.
    func listen(
        onDevicesChange: @escaping @Sendable () -> Void,
        onVolumeChange : @escaping @Sendable () -> Void
    )

    func stopListening()
}
