//
//  AudioMixerModel.swift
//  CascadeKit
//

import Dispatch
import Observation

/// AudioMixerModel is what the volume widget and the output picker read and drive. The audio
/// service pushes `SystemAudioState` in through `receive`; the user's gestures go out through the
/// `SystemAudioControlling` seam, and the model shows their effect at once, before the system
/// confirms, so a drag never waits for a round trip.
///
/// A drag or a scroll burst can produce many levels per frame, and each controller call crosses
/// to the audio queue. So `adjust` keeps only the latest level and schedules a single main-queue
/// flush when none is pending: one hop per burst, no timer, nothing woken while idle. The level
/// is paired with the device it was made for, and the flush drops it if the default output moved
/// on meanwhile.
///
/// The optimistic state is a guess: the next `receive` replaces an optimistic mute or selection
/// the system did not confirm, so a refused command heals itself without a rollback path.
@MainActor
@Observable
public final class AudioMixerModel {

    public private(set) var system: SystemAudioState?

    public private(set) var isAdjusting = false

    /// allowsSeveralOutputs is the picker's toggle between choosing one output and building a
    /// multi-output.
    public var allowsSeveralOutputs = false

    @ObservationIgnored
    private let controller: any SystemAudioControlling

    @ObservationIgnored
    private var pendingLevel: Double?

    @ObservationIgnored
    private var pendingDevice: UInt32 = 0

    @ObservationIgnored
    private var isFlushQueued = false

    public init(controller: any SystemAudioControlling) {
        self.controller = controller
    }

    /// receive takes the service's latest reading. While the user is adjusting and the reading is
    /// for the same device, the optimistic level stays, or the thumb would jump back under the
    /// finger; a reading for another device is taken whole, since the drag's target changed.
    public func receive(_ state: SystemAudioState) {
        guard
            isAdjusting,
            let current = system,
            current.defaultDeviceID == state.defaultDeviceID
        else {
            system = state
            return
        }
        system = state.replacing(level: current.level)
    }

    public func adjust(to level: Double) {
        guard let current = system else { return }

        let clamped = Swift.min(Swift.max(level, 0), 1)
        isAdjusting   = true
        system        = current.replacing(level: clamped)
        pendingLevel  = clamped
        pendingDevice = current.defaultDeviceID
        queueFlush()
    }

    /// endAdjusting sends what is still pending and leaves the adjusting state. Flushing here
    /// means the final level never waits for the queued hop.
    public func endAdjusting() {
        flush()
        isAdjusting = false
    }

    public func toggleMute() {
        guard let current = system else { return }

        let isMuted = !current.isMuted
        system = current.replacing(isMuted: isMuted)
        controller.setMuted(isMuted, forDevice: current.defaultDeviceID)
    }

    /// choose handles a tap on an output in the picker. In single mode that output becomes the
    /// system output. In several mode it joins or leaves the selection, except that the last one
    /// can never leave: a system with no output would be silent for no reason the user chose.
    public func choose(outputUID: String) {
        guard let current = system else { return }

        var uids = [outputUID]
        if allowsSeveralOutputs {
            uids = current.selectedUIDs
            if let index = uids.firstIndex(of: outputUID) {
                guard uids.count > 1 else { return }

                uids.remove(at: index)
            } else {
                uids.append(outputUID)
            }
        }
        system = current.replacing(selectedUIDs: uids)
        controller.selectOutputs(uids)
    }

    private func queueFlush() {
        guard !isFlushQueued else { return }

        isFlushQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.flush()
            }
        }
    }

    /// flush sends the pending level, if any, and only to the device it was made for.
    private func flush() {
        isFlushQueued = false
        guard let level = pendingLevel else { return }

        pendingLevel = nil
        guard pendingDevice == system?.defaultDeviceID else { return }

        controller.setLevel(level, forDevice: pendingDevice)
    }
}
