//
//  SystemAudioMultiOutput.swift
//  Cascade
//

import CascadeKit
import CoreAudio

/// SystemAudioMultiOutput is the queue-side keeper of Cascade's multi-output: the public stacked
/// aggregate that plays the system output on several devices at once. It builds it, makes it the
/// default output, and takes it down again when the selection goes back to one device, when its
/// members vanish, when Cascade quits, and at the next launch if Cascade died with one up.
///
/// It keeps no record of which aggregate is "ours". The hardware is the record: an aggregate is
/// Cascade's when its uid starts with `multiOutputUIDPrefix`, and it is in use when it is the
/// default output. That is what lets a fresh launch clean up after a crash, because a public
/// aggregate outlives the process that made it (measured, spike question C).
///
/// One rule shapes every method: the system is never left without a valid default output. A
/// device is made default first and the aggregate it replaces is destroyed after, in that order,
/// so there is no instant where the default points at something that is gone.
///
/// Everything here runs on the service's serial queue, like the hardware it drives, and the only
/// state is a flag, so the unchecked `Sendable` is the same confinement the service's reader
/// relies on.
nonisolated final class SystemAudioMultiOutput: @unchecked Sendable {

    private let hardware: any SystemAudioHardware

    private var hasCleanedLeftovers = false
    private var destroyedCount      = 0

    init(hardware: any SystemAudioHardware) {
        self.hardware = hardware
    }

    // MARK: - Selection

    /// select makes the given outputs the system output and answers whether it worked. One uid is
    /// that device; several are a new aggregate over them, the first being its clock. A
    /// refusal at any step leaves the previous default in place: a new aggregate that cannot
    /// become the default is destroyed again.
    func select(_ uids: [String]) -> Bool {
        var seen    = Set<String>()
        let members = uids.filter { seen.insert($0).inserted }

        switch members.count {
        case 0:
            return false

        case 1:
            guard let member = members.first, hardware.setDefaultOutput(uid: member) else { return false }

            destroyAggregates(except: nil)
            return true

        default:
            guard let aggregate = hardware.createMultiOutput(subDeviceUIDs: members) else { return false }

            guard hardware.setDefaultOutput(uid: aggregate) else {
                _ = hardware.destroyAggregate(uid: aggregate)
                return false
            }
            destroyAggregates(except: aggregate)
            return true
        }
    }

    // MARK: - Lifecycle

    /// cleanUpLeftovers destroys the Cascade aggregates a crashed Cascade left behind. It runs
    /// once per process: a later start (the audio widget switched off and on) finds the live
    /// aggregate of this very process, which is no leftover. If the leftover is the current
    /// default, the system is moved off it first.
    func cleanUpLeftovers() {
        guard !hasCleanedLeftovers else { return }

        hasCleanedLeftovers = true
        leaveTheDefaultAggregate(knownOutputs: nil, keepingWithTwoOrMore: false)
        destroyAggregates(except: currentDefaultAggregate())
    }

    /// reconcile follows the devices after a change. It takes the output list the service just
    /// read, so a change of devices costs no second enumeration, and answers whether it acted.
    ///
    /// While two or more members of the active aggregate remain, it stays: Core Audio drops the
    /// missing member by itself. With one left the system moves to that device, with none to the
    /// built-in output, and the aggregate goes. Any other Cascade aggregate that is not the
    /// default (the user picked another output in System Settings) is destroyed as well.
    func reconcile(outputs: [AudioOutputDevice]) -> Bool {
        let didLeave = leaveTheDefaultAggregate(knownOutputs: outputs)
        let before   = destroyedCount
        destroyAggregates(except: currentDefaultAggregate())

        return didLeave || destroyedCount != before
    }

    /// restoreBeforeQuit moves the default output to the aggregate's clock device (or the first
    /// member still there) and destroys the aggregate. It does nothing when no Cascade aggregate
    /// is the default; one that is not the default is destroyed all the same.
    func restoreBeforeQuit() {
        leaveTheDefaultAggregate(knownOutputs: nil, keepingWithTwoOrMore: false)
        destroyAggregates(except: currentDefaultAggregate())
    }

    // MARK: - Steps

    /// currentDefaultAggregate is the uid of the default output when it is a Cascade aggregate.
    private func currentDefaultAggregate() -> String? {
        guard let uid = hardware.defaultOutput()?.uid,
              uid.hasPrefix(CoreAudioSystemVolume.multiOutputUIDPrefix)
        else { return nil }

        return uid
    }

    /// leaveTheDefaultAggregate moves the default off a Cascade aggregate when it has fewer than
    /// two members left (or at once, when `keepingWithTwoOrMore` is false), and answers whether
    /// it moved. The aggregate itself is destroyed by the caller's sweep, after the move.
    ///
    /// The target is the first member that still exists, which for the clock device is the
    /// clock; with no member left, the built-in output. With nothing to move to, the aggregate
    /// stays the default: a broken output is better than no output.
    @discardableResult
    private func leaveTheDefaultAggregate(
        knownOutputs         : [AudioOutputDevice]?,
        keepingWithTwoOrMore : Bool = true
    ) -> Bool {
        guard let aggregate = currentDefaultAggregate() else { return false }

        let realOutputs = (knownOutputs ?? hardware.outputDevices())
            .filter { !$0.uid.hasPrefix(CoreAudioSystemVolume.multiOutputUIDPrefix) }
        let present   = Set(realOutputs.map(\.uid))
        let surviving = (hardware.subDeviceUIDs(ofAggregate: aggregate) ?? []).filter { present.contains($0) }

        if keepingWithTwoOrMore && surviving.count >= 2 { return false }

        let builtIn = realOutputs.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        guard let target = surviving.first ?? builtIn?.uid ?? realOutputs.first?.uid else { return false }

        return hardware.setDefaultOutput(uid: target)
    }

    /// destroyAggregates removes every Cascade aggregate except the one named, which is the
    /// default output if there is one. Called after the default moved, never before.
    private func destroyAggregates(except keptUID: String?) {
        for uid in hardware.aggregateUIDs(withPrefix: CoreAudioSystemVolume.multiOutputUIDPrefix) where uid != keptUID {
            if hardware.destroyAggregate(uid: uid) { destroyedCount += 1 }
        }
    }
}
