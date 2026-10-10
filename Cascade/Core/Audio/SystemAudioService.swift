//
//  SystemAudioService.swift
//  Cascade
//

import CascadeContracts
import CascadeKit
import Dispatch

/// SystemAudioService is the app side of the volume bar and the output picker. It reads the
/// system output through `SystemAudioHardware`, turns what it finds into `SystemAudioState` for
/// its `AudioMixerModel`, and carries the model's commands back to the hardware.
///
/// The HAL can block, so it never runs on the main thread. Every hardware call, command and
/// snapshot happens on the serial queue the service is given; a snapshot is then delivered with
/// one main-queue hop. Nothing runs between events: no timer, no polling, the hardware's
/// listeners are the only thing that wake the queue.
///
/// A command carries the HAL id of the device it was meant for. The queue compares it with the
/// default output read at that moment and drops the command on a mismatch, because a level meant
/// for the headphones must never land on the speakers the user switched to a moment ago.
///
/// The Bluetooth identities are attached on the main actor, at delivery, and the service keeps
/// the last reading without them. So there is one copy of the identities, confined to the main
/// actor, and a new identity republishes the last reading without touching the hardware.
///
/// The model keeps its controller, which is the service, so the two hold each other for the life
/// of the app. The service is created once and lives as long as the notch does.
@MainActor
final class SystemAudioService: SystemAudioControlling {

    /// multiOutputUIDPrefix marks the aggregates Cascade builds for several outputs; they are an
    /// implementation of the selection, never an output the user picks.
    nonisolated private static let multiOutputUIDPrefix = CoreAudioSystemVolume.multiOutputUIDPrefix

    nonisolated private let hardware: any SystemAudioHardware
    nonisolated private let queue   : DispatchQueue

    /// model is lazy because it takes the service as its controller, and a stored `let` cannot be
    /// given `self` before the service is fully built. It is created on first use, on the main
    /// actor, where the service lives.
    private(set) lazy var model = AudioMixerModel(controller: self)

    private var isStarted   = false
    private var lastReading : SystemAudioState?
    private var identities  : [String: AudioBluetoothIdentity] = [:]

    init(
        hardware: any SystemAudioHardware,
        queue   : DispatchQueue
    ) {
        self.hardware = hardware
        self.queue    = queue
    }

    /// start listens to the hardware and publishes the first snapshot. Calling it again does
    /// nothing.
    func start() {
        guard !isStarted else { return }

        isStarted = true
        queue.async { [self] in
            hardware.listen { [weak self] in
                self?.publishSnapshot()
            }
            publishSnapshot()
        }
    }

    func stop() {
        guard isStarted else { return }

        isStarted = false
        queue.async { [hardware] in
            hardware.stopListening()
        }
    }

    /// receive keeps the latest identity of each Bluetooth device, by its address, and republishes
    /// the last reading with it. A state that says nothing (a generic model, no ids) never
    /// replaces an identity already known: the source emits those for battery and connection
    /// events too.
    func receive(_ bluetooth: PluginBluetoothState) {
        guard bluetooth.model != .generic || bluetooth.productID != nil || bluetooth.colorID != nil
        else { return }

        let identity = AudioBluetoothIdentity(
            model    : bluetooth.model,
            productID: bluetooth.productID,
            colorID  : bluetooth.colorID
        )
        guard identities[bluetooth.deviceID] != identity else { return }

        identities[bluetooth.deviceID] = identity
        if let lastReading { publish(lastReading) }
    }

    func setLevel(
        _ level: Double,
        forDevice deviceID: UInt32
    ) {
        run(onlyIfDefaultIs: deviceID) { hardware in
            hardware.setVolume(level, of: deviceID)
        }
    }

    func setMuted(
        _ isMuted: Bool,
        forDevice deviceID: UInt32
    ) {
        run(onlyIfDefaultIs: deviceID) { hardware in
            hardware.setMuted(isMuted, of: deviceID)
        }
    }

    /// selectOutputs makes one output the system output. Several at once is the multi-output,
    /// which is not built yet (Task 10 adds it), so that case does nothing for now rather than
    /// pretending.
    func selectOutputs(_ uids: [String]) {
        guard uids.count == 1, let uid = uids.first else { return }

        queue.async { [self] in
            if !hardware.setDefaultOutput(uid: uid) { publishSnapshot() }
        }
    }

    // MARK: - Queue

    /// run does a hardware write on the queue if the default output is still the device the
    /// command was made for. A write that fails publishes a fresh snapshot: a success is
    /// announced by the hardware's own listener, but a refusal is silent, and the model's
    /// optimistic state would otherwise stay.
    private func run(
        onlyIfDefaultIs deviceID: UInt32,
        _ write                 : @escaping @Sendable (any SystemAudioHardware) -> Bool
    ) {
        queue.async { [self] in
            guard hardware.defaultOutput()?.deviceID == deviceID else { return }

            if !write(hardware) { publishSnapshot() }
        }
    }

    /// publishSnapshot reads the system output and hands it to the main actor. It runs on the
    /// queue, from a listener or from a command.
    nonisolated private func publishSnapshot() {
        guard let reading = Self.read(hardware) else { return }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.deliver(reading)
            }
        }
    }

    /// read builds one reading. The outputs carry no Bluetooth identity yet; the main actor
    /// attaches it on delivery.
    nonisolated private static func read(_ hardware: any SystemAudioHardware) -> SystemAudioState? {
        guard let output = hardware.defaultOutput() else { return nil }

        let volume  = hardware.volume(of: output.deviceID)
        let outputs = hardware.outputDevices().filter { !$0.uid.hasPrefix(multiOutputUIDPrefix) }

        var selectedUIDs = [output.uid]
        if output.uid.hasPrefix(multiOutputUIDPrefix),
           let members = hardware.subDeviceUIDs(ofAggregate: output.uid) {
            selectedUIDs = members
        }

        return SystemAudioState(
            level          : volume?.level ?? 0,
            isMuted        : volume?.isMuted ?? false,
            supportsVolume : volume?.supportsVolume ?? false,
            outputs        : outputs,
            selectedUIDs   : selectedUIDs,
            defaultDeviceID: output.deviceID
        )
    }

    // MARK: - Main actor

    private func deliver(_ reading: SystemAudioState) {
        guard isStarted else { return }

        lastReading = reading
        publish(reading)
    }

    private func publish(_ reading: SystemAudioState) {
        let outputs = reading.outputs.map { device in
            AudioOutputDevice(
                uid          : device.uid,
                name         : device.name,
                transportType: device.transportType,
                bluetooth    : PluginBluetoothAddress.outputAddress(fromUID: device.uid)
                    .flatMap { identities[$0] }
            )
        }

        model.receive(
            SystemAudioState(
                level          : reading.level,
                isMuted        : reading.isMuted,
                supportsVolume : reading.supportsVolume,
                outputs        : outputs,
                selectedUIDs   : reading.selectedUIDs,
                defaultDeviceID: reading.defaultDeviceID
            )
        )
    }
}
