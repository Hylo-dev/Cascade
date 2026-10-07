//
//  CaffeinateService.swift
//  Cascade
//

import AppKit
import CascadeContracts
import Foundation
import Synchronization

/// CaffeinateService owns Caffeinate's power assertions and the one keep-awake session they
/// serve. It is the native resource owner behind the plugin: the plugin only publishes documents
/// and asks for absolute values, while this class decides, holds the OS resource and says what
/// the truth is. It never runs on the main thread.
///
/// Every mutation happens on one serial queue, in `transact`: it takes a copy of the session
/// under the lock, runs the command on that copy with the lock released, calling IOKit as it
/// goes, and records the result under the lock in one step. Nothing is ever called while the
/// lock is held, so a reader of `state` never waits on IOKit. Because only the queue mutates,
/// nothing can slip in between the copy and the record: a command can neither double-acquire nor
/// leak an assertion, and a user gesture and the deadline timer simply take turns. The lock
/// exists for the other threads, those that read `state` and swap the emitter.
///
/// Time is one `DispatchSourceTimer` on a wall-clock deadline at `endsAt`, created once and
/// reprogrammed only when `endsAt` changes; with no timed session it points at the end of time
/// and the process has no timer due. A wall-clock deadline keeps counting while the Mac sleeps
/// and follows a clock change, and the wake notification re-checks the end as a second line.
/// Beneath both, the assertions carry an IOKit timeout of their own, so the Mac sleeps on time
/// even if Cascade hangs or crashes.
///
/// The service marks every endpoint of its own `nonisolated` because the app defaults to the
/// main actor, and its queue must be serial: `transact` checks it.
nonisolated final class CaffeinateService: Sendable {

    /// activityLifetime is the longest a live activity stays presented, the 8-hour cap
    /// `NotchActivityLifetime.maximumDuration` enforces in CascadeKit, which this class must not
    /// depend on. A gesture past it renews `activityStartedAt` so the activity presents again;
    /// a gesture inside it must not, since the notch would end and re-present the activity
    /// under the user's tap.
    static let activityLifetime: TimeInterval = 8 * 60 * 60

    /// extensionStep is what `extend` adds to the end of a timed session.
    static let extensionStep: TimeInterval = 15 * 60

    /// maximumRemaining is the longest an assertion may still have to run, the IOKit timeout limit
    /// and the top of the duration scale. Extending stops at it, so the published end never outruns
    /// the assertion that backs it.
    static let maximumRemaining: TimeInterval = 86_400

    /// maximumStaleIdentifiers bounds the identifiers whose release failed and are retried, so an
    /// identifier the system will never accept again cannot grow the list for ever.
    private static let maximumStaleIdentifiers = 16

    /// Session is everything the service knows: what it publishes and the assertion identifiers
    /// behind it. The identifiers never leave the service.
    private struct Session {

        var startedAt        : Date?
        var endsAt           : Date?
        var activityStartedAt: Date?
        var nextDuration     : CaffeinateDuration
        var keepsDisplayAwake: Bool
        var glyph            : CaffeinateGlyph
        var failure          : CaffeinateFailure?

        var systemIdentifier : UInt32?
        var displayIdentifier: UInt32?

        /// staleIdentifiers are assertions whose release failed: published state says off, but the
        /// system still lists them until their own timeout, so the next stop or expiry retries.
        var staleIdentifiers : [UInt32] = []

        var isActive: Bool { startedAt != nil }

        var published: PluginCaffeinateState {
            PluginCaffeinateState(
                startedAt        : startedAt,
                endsAt           : endsAt,
                activityStartedAt: activityStartedAt,
                nextDuration     : nextDuration,
                keepsDisplayAwake: keepsDisplayAwake,
                glyph            : glyph,
                failure          : failure
            )
        }

        func hasExpired(at now: Date) -> Bool {
            guard isActive, let endsAt else { return false }

            return endsAt <= now
        }
    }

    private struct Storage {

        var session      : Session
        var emitter      : (@Sendable (PluginCaffeinateState) -> Void)?
        var armedDeadline: Date?
    }

    private let assertions : any CaffeinateAssertions
    private let preferences: any CaffeinatePreferences
    private let clock      : @Sendable () -> Date
    private let queue      : DispatchQueue
    private let storage    : Mutex<Storage>
    private let deadline   : any DispatchSourceTimer
    private let wakeObserver  = Mutex<(any NSObjectProtocol)?>(nil)
    private let clockObserver = Mutex<(any NSObjectProtocol)?>(nil)

    /// init reads the preferences once and registers the wake observer once. The queue must be
    /// serial; it is where every command, the deadline and every emission run.
    init(
        assertions : any CaffeinateAssertions,
        preferences: any CaffeinatePreferences,
        now        : @escaping @Sendable () -> Date = { Date() },
        queue      : DispatchQueue                   = DispatchQueue(label: "Cascade.Caffeinate", qos: .utility)
    ) {
        self.assertions  = assertions
        self.preferences = preferences
        self.clock       = now
        self.queue       = queue
        self.deadline    = DispatchSource.makeTimerSource(queue: queue)
        self.storage     = Mutex(
            Storage(
                session: Session(
                    nextDuration     : preferences.nextDuration,
                    keepsDisplayAwake: preferences.keepsDisplayAwake,
                    glyph            : preferences.glyph
                )
            )
        )

        // The timer is configured, then resumed, once, and never suspended: a dispatch source
        // must not be released while suspended, and rescheduling is all disarming needs.
        deadline.setEventHandler { [weak self] in
            self?.expireNow()
        }
        deadline.schedule(wallDeadline: .distantFuture)
        deadline.resume()

        wakeObserver.withLock {
            $0 = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object : nil,
                queue  : nil
            ) { [weak self] _ in
                self?.systemDidWake()
            }
        }

        // The deadline timer runs on wall time while the assertions' IOKit timeouts are
        // monotonic: a user who moves the clock could leave the published end disagreeing with
        // them. The check is the same as after a wake, and it re-arms the timer for the new
        // wall time when nothing is due.
        clockObserver.withLock {
            $0 = NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange,
                object : nil,
                queue  : nil
            ) { [weak self] _ in
                self?.expire()
            }
        }
    }

    deinit {
        deadline.cancel()
        wakeObserver.withLock {
            if let observer = $0 {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
        }
        clockObserver.withLock {
            if let observer = $0 {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // Nothing else can be running: the last reference is gone. A session that dies with its
        // service must not outlive it as an assertion.
        var session = storage.withLock { $0.session }
        releaseEverything(of: &session)
    }

    // MARK: Public surface

    /// state is the published snapshot, read under the lock, from any thread.
    var state: PluginCaffeinateState {
        storage.withLock { $0.session.published }
    }

    /// armedDeadline is the end the deadline timer is programmed for, nil when it is disarmed. It
    /// exists so a test can see that no timer is due while no timed session runs.
    var armedDeadline: Date? {
        storage.withLock { $0.armedDeadline }
    }

    /// perform queues a command; it returns at once and the queue does the work. A command is
    /// ignored while no emitter is set, that is while the plugin holds no lease: a shortcut press
    /// with the plugin disabled must not start a session with no UI, the orphaned assertion the
    /// lifecycle forbids. The check sits here and not in `run`, because the lease ending stops the
    /// session through `run` itself. It is race-free: `setEmitter` writes the emitter under the
    /// lock before it returns, so a command queued after the lease ended sees no emitter.
    func perform(_ command: CaffeinateCommand) {
        queue.async { [self] in
            guard storage.withLock({ $0.emitter != nil }) else { return }

            run(command)
        }
    }

    /// setEmitter gives the service the place to send its snapshots, or takes it away. A new
    /// emitter first receives the current state, sent from the queue so it can never arrive after
    /// a newer one. Nil means the lease ended: the emitter is dropped at once, so nothing is
    /// emitted from then on, and the session stops, releasing its assertions, so no assertion
    /// outlives its UI.
    func setEmitter(_ emit: (@Sendable (PluginCaffeinateState) -> Void)?) {
        storage.withLock { $0.emitter = emit }

        queue.async { [self] in
            if emit == nil {
                run(.stop)
            } else {
                let (snapshot, emitter) = storage.withLock { ($0.session.published, $0.emitter) }
                emitter?(snapshot)
            }
        }
    }

    /// expire is the deadline: it ends the session if it is still due, and does nothing if a
    /// racing command already moved or ended it.
    func expire() {
        queue.async { [self] in
            expireNow()
        }
    }

    /// systemDidWake re-checks the end after sleep, as a second line behind the wall-clock timer.
    func systemDidWake() {
        expire()
    }

    /// drain waits until every command queued so far has run. It is for tests; calling it from
    /// the service's own queue would deadlock.
    func drain() {
        queue.sync {}
    }

    // MARK: Transactions

    /// transact is the only way the session changes. It runs on the queue, takes a copy of the
    /// session, lets `body` change the copy and call IOKit with no lock held, then records the
    /// copy and returns to publish. `body` must leave the copy consistent at every point it can
    /// return, since the copy is recorded whatever happened inside.
    private func transact(_ body: (_ session: inout Session, _ now: Date) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))

        let now    = clock()
        let before = storage.withLock { $0.session }
        var after  = before
        body(&after, now)

        let emitter = storage.withLock { storage -> (@Sendable (PluginCaffeinateState) -> Void)? in
            storage.session = after
            return storage.emitter
        }

        // Everything below runs with the lock released.
        if before.endsAt != after.endsAt || before.isActive != after.isActive {
            arm(deadline: after.endsAt)
        }
        persist(from: before, to: after)

        let snapshot = after.published
        if before.published != snapshot {
            emitter?(snapshot)
        }
    }

    private func run(_ command: CaffeinateCommand) {
        transact { session, now in
            // A command answers the failure of the one before it: it starts clean.
            session.failure = nil

            // A session whose end has passed but whose timer has not fired yet is over; ending
            // it first means a gesture never extends, steps or toggles a dead session.
            if session.hasExpired(at: now) {
                releaseEverything(of: &session)
            }

            switch command {
                case .start:
                    start(&session, now: now)

                case .stop:
                    releaseEverything(of: &session)

                case .toggle:
                    if session.isActive {
                        releaseEverything(of: &session)
                    } else {
                        start(&session, now: now)
                    }

                case .extend:
                    extend(&session, now: now)

                case .stepUp:
                    step(&session, now: now, up: true)

                case .stepDown:
                    step(&session, now: now, up: false)

                case .setKeepsDisplayAwake(let keepsDisplayAwake):
                    setKeepsDisplayAwake(keepsDisplayAwake, in: &session, now: now)

                case .setGlyph(let glyph):
                    session.glyph = glyph
            }

            renewActivityIfPastItsCap(&session, now: now, command: command)
        }
    }

    /// expireNow ends the session if, and only if, it still exists and its end has passed. The
    /// check runs on the copy taken at the top of the transaction, which is the same instant a
    /// racing extend either already ran (the end moved, nothing is due) or has yet to run (it
    /// will see the session off). A fire that finds nothing due programs the timer again, since
    /// a timer fires once.
    private func expireNow() {
        transact { session, now in
            guard session.hasExpired(at: now) else {
                arm(deadline: session.endsAt)
                return
            }

            releaseEverything(of: &session)
            session.failure = nil
        }
    }

    // MARK: Commands

    /// start acquires the system assertion, and the display one when the preference says so, each
    /// with the next duration as its timeout. A refusal leaves the session off and publishes the
    /// failure; if the display assertion is the one refused, the system assertion just taken is
    /// given back, so a refused start holds nothing. Starting a session that runs is a no-op.
    private func start(
        _ session: inout Session,
        now      : Date
    ) {
        guard !session.isActive else { return }

        let seconds = session.nextDuration.seconds

        let systemIdentifier: UInt32
        do throws(CaffeinateAssertionError) {
            systemIdentifier = try assertions.acquire(.system, timeout: seconds)
        } catch {
            session.failure = .assertionRefused(error.code)
            return
        }

        var displayIdentifier: UInt32?
        if session.keepsDisplayAwake {
            do throws(CaffeinateAssertionError) {
                displayIdentifier = try assertions.acquire(.display, timeout: seconds)
            } catch {
                release(systemIdentifier, keepingFailuresIn: &session)
                session.failure = .assertionRefused(error.code)
                return
            }
        }

        session.systemIdentifier  = systemIdentifier
        session.displayIdentifier = displayIdentifier
        session.startedAt         = now
        session.endsAt            = seconds.map { now + $0 }
        session.activityStartedAt = now
    }

    /// extend adds fifteen minutes to a timed session's end, up to the day an assertion can run
    /// for. An indefinite or stopped session has no end to move, and one already at the limit has
    /// nothing to add: both are no-ops.
    private func extend(
        _ session: inout Session,
        now      : Date
    ) {
        guard session.isActive, let endsAt = session.endsAt else { return }

        let newEnd = min(endsAt + Self.extensionStep, now + Self.maximumRemaining)
        guard newEnd > endsAt else { return }

        if let code = retime(&session, to: newEnd, now: now) {
            session.failure = .extensionRefused(code)
        }
    }

    /// step moves the duration one step on the scale. While off it moves the next duration. While
    /// a session runs the stepper shows the time left rounded up to the scale, so a step starts
    /// from that value and sets the end to now plus the neighbouring one: from 15 minutes down
    /// is indefinite, and up from indefinite is fifteen minutes from now. The next duration
    /// follows the stepped value, but only if the assertions accepted it.
    private func step(
        _ session: inout Session,
        now      : Date,
        up       : Bool
    ) {
        guard session.isActive else {
            let neighbour = up ? session.nextDuration.steppedUp() : session.nextDuration.steppedDown()
            if let neighbour { session.nextDuration = neighbour }
            return
        }

        let shown: CaffeinateDuration = session.endsAt.map { .timeLeft($0.timeIntervalSince(now)) } ?? .indefinite
        guard let target = up ? shown.steppedUp() : shown.steppedDown() else { return }

        if let code = retime(&session, to: target.seconds.map { now + $0 }, now: now) {
            session.failure = .extensionRefused(code)
        } else {
            session.nextDuration = target
        }
    }

    /// setKeepsDisplayAwake changes the preference and, during a session, takes or gives back the
    /// display assertion alone, leaving the system one untouched. Turning it on is refused as a
    /// whole if the system refuses the assertion: the preference stays as it was and the failure
    /// is published.
    private func setKeepsDisplayAwake(
        _ keepsDisplayAwake: Bool,
        in session         : inout Session,
        now                : Date
    ) {
        guard keepsDisplayAwake != session.keepsDisplayAwake else { return }

        if session.isActive {
            if keepsDisplayAwake {
                do throws(CaffeinateAssertionError) {
                    session.displayIdentifier = try assertions.acquire(
                        .display,
                        timeout: session.endsAt.map { $0.timeIntervalSince(now) }
                    )
                } catch {
                    session.failure = .assertionRefused(error.code)
                    return
                }
            } else if let identifier = session.displayIdentifier {
                session.displayIdentifier = nil
                release(identifier, keepingFailuresIn: &session)
            }
        }
        session.keepsDisplayAwake = keepsDisplayAwake
    }

    /// renewActivityIfPastItsCap starts a new activity when the user touches a session whose
    /// activity the notch has already ended at its lifetime cap. Inside the cap it leaves
    /// `activityStartedAt` alone, so the live activity is never ended and re-presented under the
    /// user's finger. The glyph is a setting, not a gesture on the session.
    private func renewActivityIfPastItsCap(
        _ session: inout Session,
        now      : Date,
        command  : CaffeinateCommand
    ) {
        if case .setGlyph = command { return }
        guard session.isActive,
              let activityStartedAt = session.activityStartedAt,
              now >= activityStartedAt + Self.activityLifetime
        else { return }

        session.activityStartedAt = now
    }

    // MARK: IOKit steps

    /// retime sets the IOKit timeout of every held assertion to the new end, in place and never
    /// releasing one first. The timeout is measured from `now`, a moment before the system gets it,
    /// so it runs a few milliseconds past the published end, never short of it. If any assertion
    /// refuses, the ones already changed are put back, best effort, and the session and its end
    /// stay as they were: the answer is the refusing code, nil when all accepted.
    private func retime(
        _ session: inout Session,
        to newEnd: Date?,
        now      : Date
    ) -> Int32? {
        let timeout         = newEnd.map { $0.timeIntervalSince(now) }
        let previousTimeout = session.endsAt.map { $0.timeIntervalSince(now) }
        var changed: [UInt32] = []

        for identifier in [session.systemIdentifier, session.displayIdentifier].compactMap({ $0 }) {
            do throws(CaffeinateAssertionError) {
                try assertions.setTimeout(timeout, of: identifier)
                changed.append(identifier)
            } catch {
                for restored in changed {
                    try? assertions.setTimeout(previousTimeout, of: restored)
                }
                return error.code
            }
        }

        session.endsAt = newEnd
        return nil
    }

    /// releaseEverything ends the session: it gives back the held assertions and every stale one
    /// still waiting for a retry, and clears the dates. A release that fails keeps its identifier
    /// for the next stop or expiry; the published state is off regardless, since the assertion
    /// carries its own timeout and will end by itself.
    private func releaseEverything(of session: inout Session) {
        let identifiers = session.staleIdentifiers + [session.systemIdentifier, session.displayIdentifier].compactMap { $0 }

        session.staleIdentifiers  = []
        session.systemIdentifier  = nil
        session.displayIdentifier = nil
        session.startedAt         = nil
        session.endsAt            = nil
        session.activityStartedAt = nil

        for identifier in identifiers {
            release(identifier, keepingFailuresIn: &session)
        }
    }

    private func release(
        _ identifier         : UInt32,
        keepingFailuresIn session: inout Session
    ) {
        do throws(CaffeinateAssertionError) {
            try assertions.release(identifier)
        } catch {
            session.staleIdentifiers.append(identifier)
            if session.staleIdentifiers.count > Self.maximumStaleIdentifiers {
                session.staleIdentifiers.removeFirst()
            }
        }
    }

    // MARK: Timer and preferences

    /// arm programs the deadline timer for `endsAt`, or disarms it by pointing it at the end of
    /// time when there is none. The leeway lets the system coalesce the wake with others, a
    /// quarter of a second being invisible beside the countdown the kernel draws.
    private func arm(deadline endsAt: Date?) {
        if let endsAt {
            deadline.schedule(wallDeadline: Self.wallTime(of: endsAt), leeway: .milliseconds(250))
        } else {
            deadline.schedule(wallDeadline: .distantFuture)
        }
        storage.withLock { $0.armedDeadline = endsAt }
    }

    private static func wallTime(of date: Date) -> DispatchWallTime {
        let seconds = max(0, date.timeIntervalSince1970)
        let whole   = seconds.rounded(.down)
        let nanos   = min(999_999_999, ((seconds - whole) * 1_000_000_000).rounded(.up))

        return DispatchWallTime(timespec: timespec(tv_sec: Int(whole), tv_nsec: Int(nanos)))
    }

    /// persist writes only what changed, from the queue, after the lock is released.
    private func persist(
        from before: Session,
        to after   : Session
    ) {
        if before.nextDuration      != after.nextDuration      { preferences.nextDuration      = after.nextDuration }
        if before.keepsDisplayAwake != after.keepsDisplayAwake { preferences.keepsDisplayAwake = after.keepsDisplayAwake }
        if before.glyph             != after.glyph             { preferences.glyph             = after.glyph }
    }
}
