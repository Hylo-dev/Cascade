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
/// Reading is split by cost. The device list (every device, its streams, name and transport) and
/// the members of a multi-output are read when the devices change, at start and after choosing
/// an output, and kept on the queue. A change of level or mute, which a drag fires dozens of
/// times a second, re-reads only the default output and its level. A reading equal to the last
/// one delivered is not delivered again.
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
    nonisolated fileprivate static let multiOutputUIDPrefix = CoreAudioSystemVolume.multiOutputUIDPrefix

    nonisolated private let hardware: any SystemAudioHardware
    nonisolated private let queue   : DispatchQueue
    nonisolated private let reader  : SystemAudioQueueReader

    nonisolated private let multiOutput: SystemAudioMultiOutput

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
        self.reader   = SystemAudioQueueReader(hardware: hardware)

        self.multiOutput = SystemAudioMultiOutput(hardware: hardware)
    }

    /// start listens to the hardware and publishes the first snapshot. Calling it again does
    /// nothing.
    func start() {
        guard !isStarted else { return }

        isStarted = true
        queue.async { [self] in
            reader.forgetLastDelivery()
            multiOutput.cleanUpLeftovers()
            hardware.listen(
                onDevicesChange: { [weak self] in self?.devicesDidChange() },
                onVolumeChange : { [weak self] in self?.publishSnapshot() }
            )
            devicesDidChange()
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

    /// selectOutputs makes the given outputs the system output: one device directly, several as
    /// Cascade's multi-output aggregate (`SystemAudioMultiOutput`). A selection the hardware
    /// refuses publishes the reading anyway, so the selector snaps back to what is really playing.
    func selectOutputs(_ uids: [String]) {
        queue.async { [self] in
            let didSelect = multiOutput.select(uids)
            reader.refreshDevices()
            publishSnapshot(forced: !didSelect)
        }
    }

    /// restoreBeforeQuit gives the system a real default output back before Cascade exits, and
    /// destroys the multi-output if one is active. It is the one place that waits on the main
    /// thread, because a quitting process has no later moment: it is bounded to two seconds, so
    /// a stuck HAL cannot hold the quit, and it is a no-op when no aggregate is active.
    ///
    /// It is `nonisolated` on purpose: a work item built inside a main-actor method inherits the
    /// main actor, and running it on the service's queue would trap.
    nonisolated func restoreBeforeQuit() {
        let work = DispatchWorkItem { [multiOutput] in
            multiOutput.restoreBeforeQuit()
        }
        queue.async(execute: work)
        _ = work.wait(timeout: .now() + 2)
    }

    // MARK: - Queue

    /// run does a hardware write on the queue if the default output is still the device the
    /// command was made for. A write that fails publishes a fresh snapshot even if it equals the
    /// last one: a success is announced by the hardware's own listener, but a refusal is silent,
    /// and the model's optimistic state would otherwise stay.
    private func run(
        onlyIfDefaultIs deviceID: UInt32,
        _ write                 : @escaping @Sendable (any SystemAudioHardware) -> Bool
    ) {
        queue.async { [self] in
            guard hardware.defaultOutput()?.deviceID == deviceID else { return }

            if !write(hardware) { publishSnapshot(forced: true) }
        }
    }

    /// devicesDidChange re-reads the device list and the multi-output members, lets the
    /// multi-output follow a member that came or went (re-reading if it moved the default), then
    /// publishes.
    /// It runs on the queue, from the hardware's devices listener or from start.
    nonisolated private func devicesDidChange() {
        reader.refreshDevices()
        if multiOutput.reconcile(outputs: reader.outputs) { reader.refreshDevices() }
        publishSnapshot()
    }

    /// publishSnapshot reads the default output and its level, with the cached device list, and
    /// hands the result to the main actor unless it is the one already delivered. `forced` skips
    /// that comparison. It runs on the queue, from a listener or from a command.
    nonisolated private func publishSnapshot(forced: Bool = false) {
        guard let reading = reader.reading(forced: forced) else { return }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.deliver(reading)
            }
        }
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

/// SystemAudioQueueReader is the service's queue-side memory: the device list, the members of the
/// default output when it is a multi-output, and the last reading handed to the main actor.
///
/// All of it is touched only on the service's serial queue, which is what makes the unchecked
/// `Sendable` honest: the service owns it from `nonisolated` code that runs there and from
/// nowhere else.
nonisolated private final class SystemAudioQueueReader: @unchecked Sendable {

    private let hardware: any SystemAudioHardware

    private(set) var outputs : [AudioOutputDevice] = []
    private var members      : (uid: String, uids: [String])?
    private var lastDelivered: SystemAudioState?

    init(hardware: any SystemAudioHardware) {
        self.hardware = hardware
    }

    /// forgetLastDelivery makes the next reading go out whatever it is, after a start.
    func forgetLastDelivery() {
        lastDelivered = nil
    }

    /// refreshDevices re-reads what only a change of devices can alter: the outputs, which hide
    /// Cascade's own aggregates, and the members of the default output if it is one.
    func refreshDevices() {
        outputs = hardware.outputDevices().filter { !$0.uid.hasPrefix(SystemAudioService.multiOutputUIDPrefix) }
        members = nil
        if let output = hardware.defaultOutput() { _ = memberUIDs(of: output.uid) }
    }

    /// reading builds the state from the cached devices and the default output's level, or nil
    /// when there is no default output or the state is the one delivered last.
    func reading(forced: Bool) -> SystemAudioState? {
        guard let output = hardware.defaultOutput() else { return nil }

        let volume = hardware.volume(of: output.deviceID)
        let state  = SystemAudioState(
            level          : volume?.level ?? 0,
            isMuted        : volume?.isMuted ?? false,
            supportsVolume : volume?.supportsVolume ?? false,
            outputs        : outputs,
            selectedUIDs   : memberUIDs(of: output.uid) ?? [output.uid],
            defaultDeviceID: output.deviceID
        )
        guard forced || state != lastDelivered else { return nil }

        lastDelivered = state
        return state
    }

    /// memberUIDs gives the members of a multi-output default, read once and kept until the
    /// devices change; nil for any other output.
    private func memberUIDs(of uid: String) -> [String]? {
        guard uid.hasPrefix(SystemAudioService.multiOutputUIDPrefix) else { return nil }

        if let members, members.uid == uid { return members.uids }

        guard let uids = hardware.subDeviceUIDs(ofAggregate: uid) else { return nil }

        members = (uid, uids)
        return uids
    }
}
