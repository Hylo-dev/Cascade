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
/// How a session ends is a `CaffeinateTarget`: never, after a duration, or at a time of day. An
/// end time is resolved to an instant when the session starts, in the injected calendar's time
/// zone, so a daylight saving change moves it with the wall clock. While a session runs, the
/// target commands move its end in place (`setTimeout` on the held assertions), never releasing
/// first; while none runs they only change what the next session will do. The last duration and
/// the last end time chosen are remembered apart, so switching the mode brings them back.
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

    /// shortestUntil is the least an end time may be ahead of now to be taken, one minute: below it
    /// the instant is already past by the time the assertions hear of it.
    private static let shortestUntil: TimeInterval = 60

    /// maximumStaleIdentifiers bounds the identifiers whose release failed and are retried, so an
    /// identifier the system will never accept again cannot grow the list for ever.
    private static let maximumStaleIdentifiers = 16

    /// Session is everything the service knows: what it publishes and the assertion identifiers
    /// behind it. The identifiers never leave the service.
    private struct Session {

        var startedAt        : Date?
        var endsAt           : Date?
        var activityStartedAt: Date?
        var nextTarget       : CaffeinateTarget

        /// lastDuration is the last duration the user chose, in minutes; lastUntil the last end
        /// time, as a minute of the local day. They are what switching the mode restores.
        var lastDuration     : Int
        var lastUntil        : Int
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
                nextTarget       : nextTarget,
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

        var session        : Session
        var emitter        : (@Sendable (PluginCaffeinateState) -> Void)?
        var armedDeadline  : Date?
        var sessionsAllowed = false
    }

    private let assertions : any CaffeinateAssertions
    private let preferences: any CaffeinatePreferences
    private let clock      : @Sendable () -> Date
    private let calendar   : Calendar
    private let queue      : DispatchQueue
    private let storage    : Mutex<Storage>
    private let deadline   : any DispatchSourceTimer
    private let wakeObserver  = Mutex<(any NSObjectProtocol)?>(nil)
    private let clockObserver = Mutex<(any NSObjectProtocol)?>(nil)

    /// init reads the preferences once and registers the wake observer once. The queue must be
    /// serial; it is where every command, the deadline and every emission run. The calendar
    /// decides what a time of day means: its time zone is the user's, `.current` in the app and a
    /// fixed one in tests. A remembered duration or end time that was never chosen falls back to
    /// the target already stored when it is of that kind, then to an hour, and to the next full
    /// hour of the calendar.
    init(
        assertions : any CaffeinateAssertions,
        preferences: any CaffeinatePreferences,
        now        : @escaping @Sendable () -> Date = { Date() },
        calendar   : Calendar                       = .current,
        queue      : DispatchQueue                   = DispatchQueue(label: "Cascade.Caffeinate", qos: .utility)
    ) {
        self.assertions  = assertions
        self.preferences = preferences
        self.clock       = now
        self.calendar    = calendar
        self.queue       = queue
        self.deadline    = DispatchSource.makeTimerSource(queue: queue)

        let nextTarget   = preferences.nextTarget
        var lastDuration = preferences.lastDurationMinutes
        var lastUntil    = preferences.lastUntilMinuteOfDay
        switch nextTarget {
            case .duration(let minutes)  : lastDuration = lastDuration ?? minutes
            case .until(let minuteOfDay) : lastUntil    = lastUntil ?? minuteOfDay
            case .indefinite             : break
        }
        let nextFullHour = (calendar.component(.hour, from: now()) + 1) % 24 * 60
        self.storage     = Mutex(
            Storage(
                session: Session(
                    nextTarget       : nextTarget,
                    lastDuration     : lastDuration ?? 60,
                    lastUntil        : lastUntil ?? nextFullHour,
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

    /// perform queues a command; it returns at once and the queue does the work. A session command
    /// is ignored while sessions are not allowed, that is while the plugin is not active (switched
    /// off, quarantined or disabled after a hang): a shortcut press then must not start a session
    /// with no UI to show or stop it, the orphaned assertion the lifecycle forbids. A preference
    /// command (`setGlyph`, `setKeepsDisplayAwake`) always runs, so Settings keeps working while the
    /// plugin is off; that is safe because no session can be active while sessions are not allowed,
    /// so there is no assertion to touch. The check sits here and not in `run`, because withdrawing
    /// the permission stops the session through `run` itself. It is race-free:
    /// `setSessionsAllowed` writes the permission under the lock before it returns, so a command
    /// queued after it sees the new value.
    ///
    /// A target command (`setMode`, `setDuration`, `setUntil`) is a preference while no session
    /// runs, since it only chooses what the next one does, and a session command while one does,
    /// since it moves the running end. So it passes the gate when sessions are allowed, or when
    /// none is running; a stale one that meets a session the withdrawal has not yet stopped is
    /// ignored, and the stop that follows it ends the session anyway.
    ///
    /// The permission is deliberately not the emitter. The emitter follows the source's lease,
    /// which the kernel also ends when PluginHost goes away (a crash of any plugin, a memory kill,
    /// a restart from Settings); the session must outlive that, since the service owns it and
    /// needs no PluginHost to hold an assertion.
    func perform(_ command: CaffeinateCommand) {
        queue.async { [self] in
            let (allowed, running) = storage.withLock { ($0.sessionsAllowed, $0.session.isActive) }
            guard command.isPreference || allowed || (command.isTargetChange && !running) else { return }

            run(command)
        }
    }

    /// setSessionsAllowed says whether a session may run, following the plugin's own state:
    /// allowed while it is active, whatever PluginHost is doing. Withdrawing the permission stops
    /// a running session, releasing its assertions and emitting off if an emitter is attached, so
    /// no assertion outlives a plugin the user switched off or the kernel quarantined. Sessions
    /// start out not allowed: nothing may start before the engine said the plugin is active.
    func setSessionsAllowed(_ allowed: Bool) {
        storage.withLock { $0.sessionsAllowed = allowed }

        guard !allowed else { return }

        queue.async { [self] in
            run(.stop)
        }
    }

    /// setEmitter gives the service the place to send its snapshots, or takes it away. A new
    /// emitter first receives the current state, sent from the queue so it can never arrive after
    /// a newer one: this is how the plugin catches up with a session that went on, or ended,
    /// while PluginHost was away. Nil means the lease ended: the emitter is dropped at once, so
    /// nothing is emitted from then on, and the session is left alone. Its fate is decided by
    /// `setSessionsAllowed`, never by the lease.
    func setEmitter(_ emit: (@Sendable (PluginCaffeinateState) -> Void)?) {
        storage.withLock { $0.emitter = emit }

        guard emit != nil else { return }

        queue.async { [self] in
            let (snapshot, emitter) = storage.withLock { ($0.session.published, $0.emitter) }
            emitter?(snapshot)
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
            // it first means a gesture never steps or toggles a dead session.
            let hadExpired = session.hasExpired(at: now)
            if hadExpired {
                releaseEverything(of: &session)
            }

            switch command {
                case .start:
                    start(&session, now: now)

                case .stop:
                    releaseEverything(of: &session)

                case .toggle:
                    // A toggle that lands on a session already past its end (inside the timer's
                    // leeway, or just after a wake) was pressed to stop what the user saw running:
                    // ending it is the whole answer, never a new session.
                    if session.isActive {
                        releaseEverything(of: &session)
                    } else if !hadExpired {
                        start(&session, now: now)
                    }

                case .setMode(let kind):
                    setMode(kind, in: &session, now: now)

                case .setDuration(let minutes):
                    setDuration(minutes, in: &session, now: now)

                case .setUntil(let date):
                    setUntil(date, in: &session, now: now)

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
    /// racing step either already ran (the end moved, nothing is due) or has yet to run (it
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
    /// with the time to the next target's end as its timeout, none for an indefinite one. A refusal leaves the session off and publishes the
    /// failure; if the display assertion is the one refused, the system assertion just taken is
    /// given back, so a refused start holds nothing. Starting a session that runs is a no-op.
    private func start(
        _ session: inout Session,
        now      : Date
    ) {
        guard !session.isActive else { return }

        let end     = session.nextTarget.end(startingAt: now, calendar: calendar)
        let seconds = end.map { $0.timeIntervalSince(now) }

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
        session.endsAt            = end
        session.activityStartedAt = now
    }

    /// setMode picks how the next or the running session ends. While off it makes the next target
    /// the last value of that kind (indefinite has none). While a session runs, indefinite
    /// removes the end; a duration or an end time keeps the end it has, and only when the session
    /// was indefinite applies that kind's last value, counted from now. The target follows only if
    /// the assertions accepted the change.
    private func setMode(
        _ kind  : CaffeinateTargetKind,
        in session: inout Session,
        now     : Date
    ) {
        let target: CaffeinateTarget = switch kind {
            case .indefinite: .indefinite
            case .duration  : .duration(minutes: session.lastDuration)
            case .until     : .until(minuteOfDay: session.lastUntil)
        }

        guard session.isActive else {
            session.nextTarget = target
            return
        }

        if kind != .indefinite, session.endsAt != nil {
            session.nextTarget = target
        } else {
            retarget(&session, to: target, end: target.end(startingAt: now, calendar: calendar), now: now)
        }
    }

    /// setDuration is the ruler's absolute duration, in minutes. One off the scale is ignored.
    /// While off it is stored as the next target and remembered; while a session runs the end
    /// becomes now plus that many minutes.
    private func setDuration(
        _ minutes: Int,
        in session: inout Session,
        now      : Date
    ) {
        guard CaffeinateTarget.isValid(minutes: minutes) else { return }

        let target = CaffeinateTarget.duration(minutes: minutes)

        guard session.isActive else {
            session.nextTarget  = target
            session.lastDuration = minutes
            return
        }

        retarget(&session, to: target, end: target.end(startingAt: now, calendar: calendar), now: now)
    }

    /// setUntil is the ruler's absolute end time, an instant. It is rounded to the nearest quarter
    /// hour and ignored unless the result is between a minute and a day ahead, the bounds the
    /// ruler can reach: a past or distant instant is a stale or hostile one. While off it is
    /// stored as the minute of the day in the calendar's time zone and remembered; while a
    /// session runs the end moves to that instant.
    private func setUntil(
        _ instant: Date,
        in session: inout Session,
        now      : Date
    ) {
        let raw = instant.timeIntervalSince(now)
        guard raw >= Self.shortestUntil, raw <= CaffeinateTarget.maximumLength else { return }

        let quarter = TimeInterval(CaffeinateTarget.step * 60)
        let end     = Date(timeIntervalSince1970: (instant.timeIntervalSince1970 / quarter).rounded() * quarter)
        let rounded = end.timeIntervalSince(now)
        guard rounded >= Self.shortestUntil, rounded <= CaffeinateTarget.maximumLength else { return }

        let parts       = calendar.dateComponents([.hour, .minute], from: end)
        let minuteOfDay = ((((parts.hour ?? 0) * 60 + (parts.minute ?? 0) + 7) / CaffeinateTarget.step) * CaffeinateTarget.step) % CaffeinateTarget.minutesPerDay
        let target      = CaffeinateTarget.until(minuteOfDay: minuteOfDay)

        guard session.isActive else {
            session.nextTarget = target
            session.lastUntil  = minuteOfDay
            return
        }

        retarget(&session, to: target, end: end, now: now)
    }

    /// retarget moves a running session's end in place and, only if the assertions accepted it,
    /// makes `target` the next one and remembers it. A refusal leaves the session, its end and the
    /// target as they were and publishes `extensionRefused`. Nothing is called when the end does
    /// not move.
    private func retarget(
        _ session: inout Session,
        to target: CaffeinateTarget,
        end      : Date?,
        now      : Date
    ) {
        if end != session.endsAt, let code = retime(&session, to: end, now: now) {
            session.failure = .extensionRefused(code)
            return
        }

        session.nextTarget = target
        switch target {
            case .duration(let minutes)  : session.lastDuration = minutes
            case .until(let minuteOfDay) : session.lastUntil    = minuteOfDay
            case .indefinite             : break
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
        if before.nextTarget        != after.nextTarget        { preferences.nextTarget        = after.nextTarget }
        if before.lastDuration      != after.lastDuration      { preferences.lastDurationMinutes  = after.lastDuration }
        if before.lastUntil         != after.lastUntil         { preferences.lastUntilMinuteOfDay = after.lastUntil }
        if before.keepsDisplayAwake != after.keepsDisplayAwake { preferences.keepsDisplayAwake = after.keepsDisplayAwake }
        if before.glyph             != after.glyph             { preferences.glyph             = after.glyph }
    }
}
