//
//  AudioHostSession.swift
//  Cascade
//

import CascadeContracts
import Dispatch
import os

/// AudioHostSession is the decision core of the per-app audio service: it owns the intents and
/// the life of the connection to AudioHost, and it runs entirely on the service's serial queue.
/// The main-actor `AppAudioService` only hands it commands and receives what it delivers.
///
/// AudioHost runs only while something needs it: the mixer is on screen, or at least one stored
/// intent is not neutral and so must be enforced. When neither holds the session disconnects and
/// the service exits on its own, since it keeps no state; the intents live here, in the store.
///
/// The connection moves through five phases. `connecting` waits for the handshake, which
/// replays the whole intent set so a fresh AudioHost converges on what the user chose; `running`
/// carries the deltas; a loss moves to `backingOff` until the supervisor's pause ends, or to
/// `givenUp`, where the apps play natively until `restart`. Every link has an epoch that grows
/// whenever one is abandoned, and every callback carries the epoch it was made for, so a reply,
/// a snapshot or a timer from a link that no longer exists is dropped at the door.
///
/// Three things count as a loss. A link that breaks without our asking is a `crash`. A command
/// unanswered for three seconds is a `hang`: the process is killed, because a hung AudioHost can
/// hold a tap on someone's audio. A footprint over 64 MiB, checked after each reply, is an
/// `overMemory` kill. The deadline is one outstanding timer for the oldest unanswered command,
/// not a timer per command: a slider drag sends dozens of commands a second and must not queue
/// dozens of timers. Time is injected twice, `clock` and `schedule`, and nothing polls.
///
/// `@unchecked Sendable` is justified by confinement: every mutable property is read and written
/// only on `queue`. The `let`s are immutable and the connection is `Sendable`.
nonisolated final class AudioHostSession: @unchecked Sendable {

    private enum Phase {

        case stopped
        case connecting
        case running
        case backingOff
        case givenUp
    }

    private let connection     : any AudioHostConnecting
    private let store          : AudioIntentStore
    private let queue          : DispatchQueue
    private let clock          : @Sendable () -> Duration
    private let schedule       : @Sendable (Duration, @escaping @Sendable () -> Void) -> Void
    private let deliverSnapshot: @Sendable (AudioHostSnapshot) -> Void
    private let deliverStatus  : @Sendable (AudioHostStatus) -> Void
    private let logger          = Logger(subsystem: "hylo.Cascade", category: "AudioHostSession")

    // MARK: Queue-confined state

    private var supervision       = AudioHostSupervision()
    private var intents           : [AudioAppIdentity: AudioAppIntent] = [:]
    private var isMixerVisible    = false
    private var phase             = Phase.stopped
    private var status            = AudioHostStatus.idle
    private var epoch             : UInt64 = 0
    private var lastCommandID     : UInt64 = 0
    private var sentAtByCommand   : [UInt64: Duration] = [:]
    private var deadlineArmedEpoch: UInt64?

    init(
        connection     : any AudioHostConnecting,
        store          : AudioIntentStore,
        queue          : DispatchQueue,
        clock          : @escaping @Sendable () -> Duration,
        schedule       : @escaping @Sendable (Duration, @escaping @Sendable () -> Void) -> Void,
        deliverSnapshot: @escaping @Sendable (AudioHostSnapshot) -> Void,
        deliverStatus  : @escaping @Sendable (AudioHostStatus) -> Void
    ) {
        self.connection      = connection
        self.store           = store
        self.queue           = queue
        self.clock           = clock
        self.schedule        = schedule
        self.deliverSnapshot = deliverSnapshot
        self.deliverStatus   = deliverStatus
    }

    // MARK: - Entry points (any thread)

    /// start reads the stored intents on the queue and starts AudioHost if any of them needs it.
    func start() {
        queue.async { [self] in
            intents = store.load()
            reconcile()
        }
    }

    func setMixerVisible(_ isVisible: Bool) {
        queue.async { [self] in
            isMixerVisible = isVisible
            reconcile()
        }
    }

    func setIntent(
        _ intent: AudioAppIntent,
        for app : AudioAppIdentity
    ) {
        queue.async { [self] in
            change(.setIntent(app, intent), to: intent, for: app)
        }
    }

    func returnToNative(_ app: AudioAppIdentity) {
        queue.async { [self] in
            change(.returnToNative(app), to: .neutral, for: app)
        }
    }

    /// restart forgives the fault history and connects again, whatever the phase: it is what the
    /// user asks for in Settings after AudioHost was given up on.
    func restart() {
        queue.async { [self] in
            supervision.forgive()

            if phase == .connecting || phase == .running {
                connection.kill()
                abandonLink()
            } else {
                epoch += 1
            }

            setStatus(.recovering)
            connect()
        }
    }

    // MARK: - Intents

    /// change stores the new intent, saves the set and forwards the delta. The command goes
    /// before `reconcile`, which may then disconnect: a host that is no longer needed still
    /// hears the last change (typically "back to native") before it is let go.
    private func change(
        _ command: AudioHostCommand,
        to intent: AudioAppIntent,
        for app  : AudioAppIdentity
    ) {
        intents[app] = intent.isNeutral ? nil : intent
        store.save(intents)

        if phase == .running {
            send(command)
        }

        reconcile()
    }

    private var isWanted: Bool {
        isMixerVisible || !intents.isEmpty
    }

    /// reconcile starts AudioHost when it is wanted and stopped, and stops it when it is not.
    /// A running host with commands still in flight is let go only once they are answered.
    private func reconcile() {
        switch (isWanted, phase) {
            case (true, .stopped):
                connect()

            case (false, .connecting), (false, .backingOff):
                stop()

            case (false, .running) where sentAtByCommand.isEmpty:
                stop()

            case (false, .stopped):
                setStatus(.idle)

            default:
                break
        }
    }

    // MARK: - Connection life

    private func connect() {
        epoch += 1

        let linkEpoch = epoch
        phase = .connecting

        let isOpen = connection.connect(
            onSnapshot: { [weak self] snapshot in
                guard let self else { return }

                queue.async { [self] in receive(snapshot, epoch: linkEpoch) }
            },
            onLoss: { [weak self] in
                guard let self else { return }

                queue.async { [self] in lose(.crashed, epoch: linkEpoch) }
            }
        )
        guard isOpen else {
            lose(.crashed, epoch: linkEpoch)
            return
        }

        let handshake = track()
        connection.hello { [weak self] pid in
            guard let self else { return }

            queue.async { [self] in helloDidReply(pid, command: handshake, epoch: linkEpoch) }
        }
    }

    private func stop() {
        if phase == .connecting || phase == .running {
            abandonLink()
        } else {
            epoch += 1
        }

        phase = .stopped
        setStatus(.idle)
    }

    /// abandonLink drops the current connection: the epoch moves on, so nothing it still has in
    /// flight can reach the session, and what was waiting for an answer is forgotten.
    private func abandonLink() {
        epoch += 1
        sentAtByCommand.removeAll()
        connection.disconnect()
    }

    private func helloDidReply(
        _ pid          : Int32?,
        command        : UInt64,
        epoch linkEpoch: UInt64
    ) {
        guard linkEpoch == epoch, phase == .connecting else { return }

        sentAtByCommand[command] = nil

        guard pid != nil else {
            lose(.crashed, epoch: linkEpoch)
            return
        }

        phase = .running
        setStatus(.running)
        send(.replaceIntents(intents))
        reconcile()
    }

    private func receive(
        _ snapshot     : AudioHostSnapshot,
        epoch linkEpoch: UInt64
    ) {
        guard linkEpoch == epoch else { return }

        deliverSnapshot(snapshot)
    }

    /// lose handles the end of a link. A kill is ours to do for a hang or a memory breach; the
    /// supervisor then says how long to wait, or that AudioHost is given up on.
    private func lose(
        _ loss         : AudioHostSupervision.Loss,
        epoch linkEpoch: UInt64
    ) {
        guard linkEpoch == epoch, phase == .connecting || phase == .running else { return }

        if loss != .crashed {
            connection.kill()
        }

        abandonLink()

        guard let delay = supervision.lost(loss, at: clock()) else {
            logger.error("AudioHost given up on after repeated faults")
            phase = .givenUp
            setStatus(.givenUp)
            return
        }

        guard isWanted else {
            phase = .stopped
            setStatus(.idle)
            return
        }

        phase = .backingOff
        setStatus(.recovering)

        let retryEpoch = epoch
        schedule(delay) { [weak self] in
            guard let self else { return }

            queue.async { [self] in retryDidFire(epoch: retryEpoch) }
        }
    }

    private func retryDidFire(epoch retryEpoch: UInt64) {
        guard retryEpoch == epoch, phase == .backingOff else { return }

        phase = .stopped
        reconcile()
    }

    // MARK: - Commands and their deadline

    private func send(_ command: AudioHostCommand) {
        let id        = track()
        let linkEpoch = epoch

        connection.send(command) { [weak self] accepted in
            guard let self else { return }

            queue.async { [self] in commandDidReply(accepted, command: id, epoch: linkEpoch) }
        }
    }

    private func commandDidReply(
        _ accepted     : Bool?,
        command        : UInt64,
        epoch linkEpoch: UInt64
    ) {
        guard linkEpoch == epoch, phase == .running else { return }

        sentAtByCommand[command] = nil

        guard let accepted else {
            lose(.crashed, epoch: linkEpoch)
            return
        }

        if !accepted {
            logger.error("AudioHost refused a command")
        }

        if let footprint = connection.footprint(), footprint > AudioHostSupervision.memoryLimit {
            lose(.overMemory, epoch: linkEpoch)
            return
        }

        reconcile()
    }

    /// track notes that a command (or the handshake) went out and makes sure a deadline timer
    /// is armed for this link.
    private func track() -> UInt64 {
        lastCommandID += 1
        sentAtByCommand[lastCommandID] = clock()

        if deadlineArmedEpoch != epoch {
            deadlineArmedEpoch = epoch
            armDeadline(after: AudioHostSupervision.commandDeadline, epoch: epoch)
        }

        return lastCommandID
    }

    private func armDeadline(
        after delay    : Duration,
        epoch linkEpoch: UInt64
    ) {
        schedule(delay) { [weak self] in
            guard let self else { return }

            queue.async { [self] in deadlineDidFire(epoch: linkEpoch) }
        }
    }

    /// deadlineDidFire looks at the oldest unanswered command: past the deadline the link is
    /// hung; before it, the timer is armed again for the rest of the wait; with nothing in
    /// flight it simply lapses, and the next command arms a new one.
    private func deadlineDidFire(epoch linkEpoch: UInt64) {
        guard linkEpoch == epoch else { return }

        deadlineArmedEpoch = nil

        guard let oldest = sentAtByCommand.values.min() else { return }

        let waited = clock() - oldest
        if waited >= AudioHostSupervision.commandDeadline {
            lose(.hung, epoch: linkEpoch)
        } else {
            deadlineArmedEpoch = linkEpoch
            armDeadline(after: AudioHostSupervision.commandDeadline - waited, epoch: linkEpoch)
        }
    }

    private func setStatus(_ newStatus: AudioHostStatus) {
        guard newStatus != status else { return }

        status = newStatus
        deliverStatus(newStatus)
    }
}
