//
//  CaffeinateServiceTests.swift
//  CascadeTests
//

import CascadeContracts
import CascadePluginEngine
import Foundation
import Synchronization
import Testing
@testable import Cascade

/// FakeAssertions records every call the service makes and plays IOKit's part: identifiers,
/// a live set, and refusals on demand. Every call also checks the service's lock discipline: it
/// reads `service.state` from another thread and counts a violation if that read cannot finish,
/// which is what a call made while the service holds its lock would cause.
nonisolated final class FakeAssertions: CaffeinateAssertions {

    enum Call: Equatable {

        case acquire(CaffeinateAssertionKind, TimeInterval?)
        case setTimeout(CaffeinateAssertionKind, TimeInterval?)
        case release(CaffeinateAssertionKind)
    }

    private struct State {

        var nextIdentifier    : UInt32 = 100
        var calls             : [Call] = []
        var live              : [UInt32: CaffeinateAssertionKind] = [:]
        var timeouts          : [UInt32: TimeInterval] = [:]
        var acquiredCount     = 0
        var releasedCount     = 0
        var failingAcquire    : [CaffeinateAssertionKind: Int32] = [:]
        var failingSetTimeout : [CaffeinateAssertionKind: Int32] = [:]
        var failingRelease    : Int32?
        var violations        = 0
    }

    private struct WeakService {

        weak var service: CaffeinateService?
    }

    private let state   = Mutex(State())
    private let service = Mutex(WeakService())

    func watch(_ service: CaffeinateService) {
        self.service.withLock { $0.service = service }
    }

    var calls         : [Call] { state.withLock { $0.calls } }
    var acquiredCount : Int    { state.withLock { $0.acquiredCount } }
    var releasedCount : Int    { state.withLock { $0.releasedCount } }
    var liveCount     : Int    { state.withLock { $0.live.count } }
    var violations    : Int    { state.withLock { $0.violations } }

    var liveKinds: [CaffeinateAssertionKind] {
        state.withLock { state in state.live.keys.sorted().compactMap { state.live[$0] } }
    }

    func clearCalls() {
        state.withLock { $0.calls = [] }
    }

    func refuseAcquire(_ kind: CaffeinateAssertionKind, code: Int32 = 7) {
        state.withLock { $0.failingAcquire[kind] = code }
    }

    func refuseSetTimeout(_ kind: CaffeinateAssertionKind, code: Int32 = 8) {
        state.withLock { $0.failingSetTimeout[kind] = code }
    }

    func refuseRelease(_ code: Int32? = 9) {
        state.withLock { $0.failingRelease = code }
    }

    func allowEverything() {
        state.withLock {
            $0.failingAcquire    = [:]
            $0.failingSetTimeout = [:]
            $0.failingRelease    = nil
        }
    }

    func acquire(
        _ kind : CaffeinateAssertionKind,
        timeout: TimeInterval?
    ) throws(CaffeinateAssertionError) -> UInt32 {
        let outcome: (identifier: UInt32, refusal: Int32?) = state.withLock {
            $0.calls.append(.acquire(kind, timeout))
            if let code = $0.failingAcquire[kind] { return (0, code) }

            $0.nextIdentifier += 1
            $0.live[$0.nextIdentifier]     = kind
            $0.timeouts[$0.nextIdentifier] = timeout ?? 0
            $0.acquiredCount += 1
            return ($0.nextIdentifier, nil)
        }
        probeTheServiceLock()

        if let code = outcome.refusal { throw CaffeinateAssertionError(code: code) }
        return outcome.identifier
    }

    func setTimeout(
        _ timeout     : TimeInterval?,
        of identifier : UInt32
    ) throws(CaffeinateAssertionError) {
        let refusal: Int32? = state.withLock {
            guard let kind = $0.live[identifier] else { return 99 }

            $0.calls.append(.setTimeout(kind, timeout))
            if let code = $0.failingSetTimeout[kind] { return code }

            $0.timeouts[identifier] = timeout ?? 0
            return nil
        }
        probeTheServiceLock()

        if let code = refusal { throw CaffeinateAssertionError(code: code) }
    }

    func release(_ identifier: UInt32) throws(CaffeinateAssertionError) {
        let refusal: Int32? = state.withLock {
            guard let kind = $0.live[identifier] else { return 99 }

            $0.calls.append(.release(kind))
            if let code = $0.failingRelease { return code }

            $0.live[identifier] = nil
            $0.releasedCount += 1
            return nil
        }
        probeTheServiceLock()

        if let code = refusal { throw CaffeinateAssertionError(code: code) }
    }

    private func probeTheServiceLock() {
        guard let service = service.withLock({ $0.service }) else { return }

        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = service.state
            finished.signal()
        }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            state.withLock { $0.violations += 1 }
        }
    }
}

nonisolated final class InMemoryCaffeinatePreferences: CaffeinatePreferences {

    private struct Values {

        var nextTarget       : CaffeinateTarget    = .indefinite
        var lastDuration     : Int?                = nil
        var lastUntil        : Int?                = nil
        var keepsDisplayAwake: Bool                = true
        var glyph            : CaffeinateGlyph     = .cupHeatWaves
        var shortcut         : CaffeinateShortcut? = .default
        var writes           : Int                 = 0
    }

    private let values = Mutex(Values())

    var writes: Int { values.withLock { $0.writes } }

    var nextTarget: CaffeinateTarget {
        get { values.withLock { $0.nextTarget } }
        set { values.withLock { $0.nextTarget = newValue; $0.writes += 1 } }
    }

    var lastDurationMinutes: Int? {
        get { values.withLock { $0.lastDuration } }
        set { values.withLock { $0.lastDuration = newValue; $0.writes += 1 } }
    }

    var lastUntilMinuteOfDay: Int? {
        get { values.withLock { $0.lastUntil } }
        set { values.withLock { $0.lastUntil = newValue; $0.writes += 1 } }
    }

    var keepsDisplayAwake: Bool {
        get { values.withLock { $0.keepsDisplayAwake } }
        set { values.withLock { $0.keepsDisplayAwake = newValue; $0.writes += 1 } }
    }

    var glyph: CaffeinateGlyph {
        get { values.withLock { $0.glyph } }
        set { values.withLock { $0.glyph = newValue; $0.writes += 1 } }
    }

    var shortcut: CaffeinateShortcut? {
        get { values.withLock { $0.shortcut } }
        set { values.withLock { $0.shortcut = newValue; $0.writes += 1 } }
    }
}

nonisolated final class TestClock: Sendable {

    static let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private let current = Mutex(TestClock.origin)

    var now: Date {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

nonisolated final class EmittedStates: Sendable {

    private let states = Mutex<[PluginCaffeinateState]>([])

    var all  : [PluginCaffeinateState] { states.withLock { $0 } }
    var count: Int                     { states.withLock { $0.count } }

    func append(_ state: PluginCaffeinateState) {
        states.withLock { $0.append(state) }
    }

    func clear() {
        states.withLock { $0 = [] }
    }
}

nonisolated final class CaffeinateHarness: Sendable {

    let assertions : FakeAssertions
    let preferences: InMemoryCaffeinatePreferences
    let clock      : TestClock
    let emitted    : EmittedStates
    let service    : CaffeinateService

    static var utc: Calendar {
        var calendar      = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func newYork() -> Calendar {
        var calendar      = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// init builds a service with sessions allowed, an emitter already set and the initial
    /// snapshot forgotten, so a test counts only the transitions it causes.
    init(
        nextTarget       : CaffeinateTarget = .duration(minutes: 60),
        keepsDisplayAwake: Bool             = true,
        lastDuration     : Int?             = nil,
        lastUntil        : Int?             = nil,
        calendar         : @escaping @Sendable () -> Calendar = { CaffeinateHarness.utc },
        startingAt       : Date             = TestClock.origin
    ) {
        let assertions  = FakeAssertions()
        let preferences = InMemoryCaffeinatePreferences()
        let clock       = TestClock()
        let emitted     = EmittedStates()

        clock.now = startingAt
        preferences.nextTarget           = nextTarget
        preferences.keepsDisplayAwake    = keepsDisplayAwake
        preferences.lastDurationMinutes  = lastDuration
        preferences.lastUntilMinuteOfDay = lastUntil
        let service = CaffeinateService(
            assertions : assertions,
            preferences: preferences,
            now        : { clock.now },
            calendar   : calendar
        )
        assertions.watch(service)
        service.setSessionsAllowed(true)
        service.setEmitter { emitted.append($0) }
        service.drain()
        emitted.clear()

        self.assertions  = assertions
        self.preferences = preferences
        self.clock       = clock
        self.emitted     = emitted
        self.service     = service
    }

    func perform(_ command: CaffeinateCommand) {
        service.perform(command)
        service.drain()
    }
}

struct CaffeinateServiceTests {

    private let origin = TestClock.origin

    // MARK: Start and stop

    @Test
    func startAcquiresSystemAndDisplayWithTheNextDurationAsTimeout() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))

        harness.perform(.start)

        #expect(harness.assertions.calls == [.acquire(.system, 1800), .acquire(.display, 1800)])
        let state = harness.service.state
        #expect(state.startedAt         == origin)
        #expect(state.endsAt            == origin.addingTimeInterval(1800))
        #expect(state.activityStartedAt == origin)
        #expect(state.failure           == nil)
        #expect(harness.emitted.count   == 1)
    }

    @Test
    func startWithoutTheDisplayPreferenceAcquiresOnlyTheSystemAssertion() {
        let harness = CaffeinateHarness(keepsDisplayAwake: false)

        harness.perform(.start)

        #expect(harness.assertions.calls == [.acquire(.system, 3600)])
    }

    @Test
    func anIndefiniteStartHasNoTimeoutAndNoEnd() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)

        harness.perform(.start)

        #expect(harness.assertions.calls == [.acquire(.system, nil), .acquire(.display, nil)])
        #expect(harness.service.state.startedAt == origin)
        #expect(harness.service.state.endsAt    == nil)
        #expect(harness.service.state.isActive)
    }

    @Test
    func stopReleasesBothAssertionsAndClearsTheSession() {
        let harness = CaffeinateHarness()
        harness.perform(.start)
        harness.assertions.clearCalls()

        harness.perform(.stop)

        #expect(harness.assertions.calls == [.release(.system), .release(.display)])
        #expect(harness.assertions.liveCount == 0)
        let state = harness.service.state
        #expect(state.startedAt         == nil)
        #expect(state.endsAt            == nil)
        #expect(state.activityStartedAt == nil)
        #expect(state.nextTarget        == .duration(minutes: 60))
    }

    @Test
    func toggleStartsWhenOffAndStopsWhenOn() {
        let harness = CaffeinateHarness()

        harness.perform(.toggle)
        #expect(harness.service.state.isActive)

        harness.perform(.toggle)
        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
    }

    // MARK: Targets at start

    @Test
    func anUntilTargetEndsAtTheNextOccurrenceOfThatTime() {
        // origin is 08:00 UTC.
        let harness = CaffeinateHarness(nextTarget: .until(minuteOfDay: 10 * 60))

        harness.perform(.start)

        #expect(harness.assertions.calls == [.acquire(.system, 7200), .acquire(.display, 7200)])
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(7200))
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(7200))
    }

    @Test
    func anUntilTargetAcrossMidnightEndsTomorrow() {
        let harness = CaffeinateHarness(nextTarget: .until(minuteOfDay: 6 * 60))

        harness.perform(.start)

        #expect(harness.service.state.endsAt == origin.addingTimeInterval(22 * 3600))
        #expect(harness.assertions.calls.first == .acquire(.system, 22 * 3600))
    }

    @Test
    func anUntilTargetThatIsNowOrWithinFifteenMinutesGoesToTomorrow() {
        let now = CaffeinateHarness(nextTarget: .until(minuteOfDay: 8 * 60))
        now.perform(.start)
        #expect(now.service.state.endsAt == origin.addingTimeInterval(86_400))

        let soon = CaffeinateHarness(nextTarget: .until(minuteOfDay: 8 * 60 + 15))
        soon.perform(.start)
        #expect(soon.service.state.endsAt == origin.addingTimeInterval(900))
    }

    @Test
    func anUntilTargetFollowsTheWallClockAcrossADaylightSavingChange() throws {
        let newYork = CaffeinateHarness.newYork()
        // 2027-03-13 20:00 EST; the clocks go forward in the night.
        let evening = try #require(newYork.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 20)))
        let harness = CaffeinateHarness(
            nextTarget: .until(minuteOfDay: 8 * 60),
            calendar  : { newYork },
            startingAt: evening
        )

        harness.perform(.start)

        // 08:00 EDT is twelve hours on the wall and eleven on a stopwatch.
        #expect(harness.assertions.calls.first == .acquire(.system, 11 * 3600))
        #expect(harness.service.state.endsAt == evening.addingTimeInterval(11 * 3600))
    }

    @Test
    func startingDoesNotChangeTheTarget() {
        let harness = CaffeinateHarness(nextTarget: .until(minuteOfDay: 10 * 60))

        harness.perform(.start)
        harness.perform(.stop)

        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 10 * 60))
    }

    // MARK: Mode

    @Test
    func theModeWhileOffRestoresTheLastDurationAndTheLastUntil() {
        let harness = CaffeinateHarness(nextTarget: .indefinite, lastDuration: 90, lastUntil: 18 * 60)

        harness.perform(.setMode(.duration))
        #expect(harness.service.state.nextTarget == .duration(minutes: 90))
        #expect(harness.preferences.nextTarget   == .duration(minutes: 90))

        harness.perform(.setMode(.until))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))
        #expect(harness.preferences.nextTarget   == .until(minuteOfDay: 18 * 60))

        harness.perform(.setMode(.indefinite))
        #expect(harness.service.state.nextTarget == .indefinite)
        #expect(harness.preferences.nextTarget   == .indefinite)

        harness.perform(.setMode(.duration))
        #expect(harness.service.state.nextTarget == .duration(minutes: 90))
        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.emitted.count == 4)
    }

    @Test
    func withNothingRememberedTheDurationIsAnHourAndTheUntilIsTheNextFullHour() {
        // origin is 08:00 UTC: the next full hour is 09:00.
        let harness = CaffeinateHarness(nextTarget: .indefinite)

        harness.perform(.setMode(.duration))
        #expect(harness.service.state.nextTarget == .duration(minutes: 60))

        harness.perform(.setMode(.until))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 9 * 60))
    }

    @Test
    func theNextFullHourWrapsAfterTheLastHourOfTheDay() throws {
        let late = try #require(CaffeinateHarness.utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 23, minute: 20)))
        let harness = CaffeinateHarness(nextTarget: .indefinite, startingAt: late)

        harness.perform(.setMode(.until))

        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 0))
    }

    @Test
    func aTargetFromThePreferencesIsRememberedAsTheLastOfItsKind() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 45))

        harness.perform(.setMode(.indefinite))
        harness.perform(.setMode(.duration))

        #expect(harness.service.state.nextTarget == .duration(minutes: 45))
    }

    @Test
    func theDurationAndTheUntilWhileOffAreStoredAndRemembered() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)

        harness.perform(.setDuration(minutes: 120))
        #expect(harness.service.state.nextTarget == .duration(minutes: 120))
        harness.perform(.setMode(.indefinite))
        harness.perform(.setMode(.duration))
        #expect(harness.service.state.nextTarget == .duration(minutes: 120))
        #expect(harness.preferences.lastDurationMinutes == 120)

        // 18:00 UTC, ten hours ahead.
        harness.perform(.setUntil(origin.addingTimeInterval(10 * 3600)))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))
        harness.perform(.setMode(.duration))
        harness.perform(.setMode(.until))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))
        #expect(harness.preferences.lastUntilMinuteOfDay == 18 * 60)
        #expect(harness.assertions.calls.isEmpty)
    }

    @Test
    func anUntilIsStoredAsTheMinuteOfDayInTheCalendarsTimeZone() throws {
        let newYork = CaffeinateHarness.newYork()
        let noon    = try #require(newYork.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 12)))
        let harness = CaffeinateHarness(nextTarget: .indefinite, calendar: { newYork }, startingAt: noon)

        harness.perform(.setUntil(noon.addingTimeInterval(6 * 3600)))

        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))
    }

    @Test
    func anUntilRoundsToTheNearestQuarterHour() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)

        // 08:00 + 2h07m is 10:07, which rounds down to 10:00; 10:08 rounds up to 10:15.
        harness.perform(.setUntil(origin.addingTimeInterval(2 * 3600 + 7 * 60)))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 10 * 60))

        harness.perform(.setUntil(origin.addingTimeInterval(2 * 3600 + 8 * 60)))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 10 * 60 + 15))
    }

    @Test
    func aDurationOffTheScaleIsIgnoredWithoutAnEmission() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 60))

        for minutes in [0, 10, 14, 100, 1455, 1500, -15] {
            harness.perform(.setDuration(minutes: minutes))
        }

        #expect(harness.service.state.nextTarget == .duration(minutes: 60))
        #expect(harness.emitted.count == 0)
        #expect(harness.assertions.calls.isEmpty)

        harness.perform(.start)
        harness.assertions.clearCalls()
        harness.emitted.clear()
        for minutes in [0, 10, 1455] {
            harness.perform(.setDuration(minutes: minutes))
        }
        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.emitted.count == 0)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(3600))
    }

    @Test
    func anUntilInThePastOrMoreThanADayAheadIsIgnoredWithoutAnEmission() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 60))

        for offset: TimeInterval in [-3600, 0, 30, 59, 87_000, 90_000, 200_000] {
            harness.perform(.setUntil(origin.addingTimeInterval(offset)))
        }
        // 60 seconds ahead rounds to now, which is not a future end.
        harness.perform(.setUntil(origin.addingTimeInterval(60)))

        #expect(harness.service.state.nextTarget == .duration(minutes: 60))
        #expect(harness.emitted.count == 0)
        #expect(harness.assertions.calls.isEmpty)

        harness.perform(.start)
        harness.assertions.clearCalls()
        harness.emitted.clear()
        harness.perform(.setUntil(origin.addingTimeInterval(-60)))
        harness.perform(.setUntil(origin.addingTimeInterval(87_000)))
        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.emitted.count == 0)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(3600))
    }

    @Test
    func anUntilThatRoundsToExactlyADayAheadIsAccepted() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)

        // Only the rounded value is checked: a second over a day rounds to a day.
        harness.perform(.setUntil(origin.addingTimeInterval(86_401)))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 8 * 60))

        let running = CaffeinateHarness(nextTarget: .indefinite)
        running.perform(.start)
        running.perform(.setUntil(origin.addingTimeInterval(86_400)))
        #expect(running.service.state.endsAt == origin.addingTimeInterval(86_400))
    }

    // MARK: Calendar, defaults and the 24-hour edge

    /// ChangingCalendar plays a user who crosses a time zone while Cascade runs.
    nonisolated final class ChangingCalendar: Sendable {

        private let current = Mutex(CaffeinateHarness.utc)

        var calendar: Calendar { current.withLock { $0 } }

        func move(to identifier: String) {
            var calendar      = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            current.withLock { $0 = calendar }
        }
    }

    @Test
    func anUntilFollowsATimeZoneChangeWhileRunning() {
        let zone    = ChangingCalendar()
        let harness = CaffeinateHarness(nextTarget: .indefinite, calendar: { zone.calendar })
        let chosen  = origin.addingTimeInterval(10 * 3600)

        // 18:00 UTC.
        harness.perform(.setUntil(chosen))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))

        // The same instant is 13:00 in New York in January.
        zone.move(to: "America/New_York")
        harness.perform(.setUntil(chosen))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 13 * 60))
    }

    @Test
    func aStartResolvesTheEndTimeInTheZoneOfTheMoment() {
        let zone    = ChangingCalendar()
        let harness = CaffeinateHarness(nextTarget: .until(minuteOfDay: 10 * 60), calendar: { zone.calendar })

        // 10:00 UTC is two hours after the 08:00 UTC start.
        harness.perform(.start)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(2 * 3600))
        harness.perform(.stop)

        // In New York it is 03:00, so 10:00 is seven hours away.
        zone.move(to: "America/New_York")
        harness.perform(.start)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(7 * 3600))
    }

    @Test
    func theNextFullHourIsTakenFromTheMomentItIsUsed() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)

        // Days later, at 13:20, long after the service was created at 08:00.
        harness.clock.advance(by: 3 * 86_400 + 5 * 3600 + 20 * 60)
        harness.perform(.setMode(.until))

        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 14 * 60))
        #expect(harness.preferences.lastUntilMinuteOfDay == nil)

        // And for a running indefinite session it is not frozen into the preferences either.
        harness.perform(.setMode(.indefinite))
        harness.perform(.start)
        harness.clock.advance(by: 3600)
        harness.perform(.setMode(.until))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 15 * 60))
        #expect(harness.service.state.endsAt == harness.clock.now.addingTimeInterval(40 * 60))
        #expect(harness.preferences.lastUntilMinuteOfDay == nil)
    }

    @Test
    func anEndTimeJustShortOfFifteenMinutesTakesTheEarlierOccurrenceNotAnOffGridCap() {
        // 08:00:30 UTC with until 08:15: tomorrow's 08:15 is 24 h 14 m away, so today's, 14 m 30 s
        // ahead and so past the one-minute floor, is the end.
        let start   = origin.addingTimeInterval(30)
        let harness = CaffeinateHarness(nextTarget: .until(minuteOfDay: 8 * 60 + 15), startingAt: start)

        harness.perform(.start)

        #expect(harness.service.state.endsAt == origin.addingTimeInterval(900))
        #expect(harness.assertions.calls.first == .acquire(.system, 870))
    }

    @Test
    func theTwentyFiveHourDayDoesNotLeaveAnOffGridEnd() throws {
        let newYork = CaffeinateHarness.newYork()
        // The clocks go back on 2027-11-07; from 2027-11-06 20:30 EDT the next 20:15 is 24.5 h away
        // and the previous one is already past, so the cap is the last resort.
        let evening = try #require(newYork.date(from: DateComponents(year: 2027, month: 11, day: 6, hour: 20, minute: 30)))
        let late    = CaffeinateHarness(nextTarget: .until(minuteOfDay: 20 * 60 + 15), calendar: { newYork }, startingAt: evening)
        late.perform(.start)
        #expect(late.service.state.endsAt == evening.addingTimeInterval(86_400))

        // From 08:00:30 with until 08:15 the next one is 25 h 14 m away and today's is 14 m 30 s ahead.
        let morning = try #require(newYork.date(from: DateComponents(year: 2027, month: 11, day: 6, hour: 8, minute: 0, second: 30)))
        let early   = CaffeinateHarness(nextTarget: .until(minuteOfDay: 8 * 60 + 15), calendar: { newYork }, startingAt: morning)
        early.perform(.start)
        #expect(early.service.state.endsAt == morning.addingTimeInterval(870))
    }

    // MARK: A standing failure and an ignored command

    @Test
    func anIgnoredCommandLeavesAStandingFailureAlone() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 60))
        harness.assertions.refuseAcquire(.system, code: 5)
        harness.perform(.start)
        #expect(harness.service.state.failure == .assertionRefused(5))
        harness.emitted.clear()

        harness.perform(.setDuration(minutes: 10))
        harness.perform(.setUntil(origin.addingTimeInterval(-60)))
        harness.perform(.setUntil(origin.addingTimeInterval(200_000)))

        #expect(harness.service.state.failure == .assertionRefused(5))
        #expect(harness.emitted.count == 0)

        harness.perform(.setDuration(minutes: 45))
        #expect(harness.service.state.failure == nil)
        #expect(harness.emitted.count == 1)
    }

    // MARK: Mode and targets while a session runs

    @Test
    func chooseInfinityWhileRunningRemovesTheEndWithoutAGap() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 60))
        harness.perform(.start)
        harness.clock.advance(by: 600)
        harness.assertions.clearCalls()

        harness.perform(.setMode(.indefinite))

        #expect(harness.assertions.calls == [.setTimeout(.system, nil), .setTimeout(.display, nil)])
        #expect(harness.assertions.acquiredCount == 2)
        #expect(harness.assertions.releasedCount == 0)
        #expect(harness.service.state.endsAt == nil)
        #expect(harness.service.state.startedAt == origin)
        #expect(harness.service.state.nextTarget == .indefinite)
        #expect(harness.service.armedDeadline == nil)
    }

    @Test
    func chooseForOrUntilWhileTimedKeepsTheEnd() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 60), lastDuration: 90, lastUntil: 18 * 60)
        harness.perform(.start)
        harness.assertions.clearCalls()
        harness.emitted.clear()

        harness.perform(.setMode(.until))

        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(3600))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))

        harness.perform(.setMode(.duration))

        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(3600))
        #expect(harness.service.state.nextTarget == .duration(minutes: 90))
    }

    @Test
    func chooseForWhileIndefiniteAppliesTheLastDurationFromNow() {
        let harness = CaffeinateHarness(nextTarget: .indefinite, lastDuration: 90)
        harness.perform(.start)
        harness.clock.advance(by: 600)
        harness.assertions.clearCalls()

        harness.perform(.setMode(.duration))

        let end = origin.addingTimeInterval(600 + 5400)
        #expect(harness.assertions.calls == [.setTimeout(.system, 5400), .setTimeout(.display, 5400)])
        #expect(harness.service.state.endsAt == end)
        #expect(harness.service.armedDeadline == end)
        #expect(harness.service.state.nextTarget == .duration(minutes: 90))
        #expect(harness.assertions.releasedCount == 0)
    }

    @Test
    func chooseUntilWhileIndefiniteAppliesTheLastUntilFromNow() {
        let harness = CaffeinateHarness(nextTarget: .indefinite, lastUntil: 18 * 60)
        harness.perform(.start)
        harness.assertions.clearCalls()

        harness.perform(.setMode(.until))

        #expect(harness.assertions.calls == [.setTimeout(.system, 36_000), .setTimeout(.display, 36_000)])
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(36_000))
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 18 * 60))
    }

    @Test
    func settingTheDurationWhileRunningMovesTheEndWithoutReleasing() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.perform(.start)
        harness.clock.advance(by: 300)
        harness.assertions.clearCalls()
        harness.emitted.clear()

        harness.perform(.setDuration(minutes: 45))

        let end = origin.addingTimeInterval(300 + 2700)
        #expect(harness.assertions.calls == [.setTimeout(.system, 2700), .setTimeout(.display, 2700)])
        #expect(harness.assertions.acquiredCount == 2)
        #expect(harness.assertions.releasedCount == 0)
        #expect(harness.service.state.endsAt == end)
        #expect(harness.service.state.startedAt == origin)
        #expect(harness.service.state.nextTarget == .duration(minutes: 45))
        #expect(harness.service.armedDeadline == end)
        #expect(harness.emitted.count == 1)
        #expect(harness.preferences.lastDurationMinutes == 45)
    }

    @Test
    func settingTheDurationWhileRunningCanShortenAndNeverPassesADay() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 1440))
        harness.perform(.start)
        harness.clock.advance(by: 600)
        harness.assertions.clearCalls()

        harness.perform(.setDuration(minutes: 15))
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(600 + 900))

        harness.perform(.setDuration(minutes: 1440))
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(600 + 86_400))
        #expect(harness.assertions.calls.last == .setTimeout(.display, 86_400))
    }

    @Test
    func settingTheUntilWhileRunningMovesTheEndToThatInstant() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.perform(.start)
        harness.clock.advance(by: 300)
        harness.assertions.clearCalls()

        let chosen = origin.addingTimeInterval(3 * 3600)
        harness.perform(.setUntil(chosen))

        let remaining = chosen.timeIntervalSince(harness.clock.now)
        #expect(harness.assertions.calls == [.setTimeout(.system, remaining), .setTimeout(.display, remaining)])
        #expect(harness.service.state.endsAt == chosen)
        #expect(harness.service.state.nextTarget == .until(minuteOfDay: 11 * 60))
        #expect(harness.service.armedDeadline == chosen)
        #expect(harness.assertions.releasedCount == 0)
    }

    @Test
    func settingTheUntilWhileRunningRoundsTheEnd() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)
        harness.perform(.start)
        harness.assertions.clearCalls()

        harness.perform(.setUntil(origin.addingTimeInterval(3 * 3600 + 400)))

        // 11:06:40 rounds to 11:00.
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(3 * 3600))
    }

    @Test
    func aTargetChangeAfterExpiryDoesNotTouchADeadSession() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15), lastDuration: 90)
        harness.perform(.start)
        harness.clock.advance(by: 901)
        harness.assertions.clearCalls()

        harness.perform(.setMode(.duration))

        #expect(!harness.assertions.calls.contains { if case .setTimeout = $0 { true } else { false } })
        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.service.state.nextTarget == .duration(minutes: 90))
    }

    // MARK: Target commands and the session gate

    /// Mode and target commands are preferences while no session runs and session commands while
    /// one does; the second case cannot be reached with sessions not allowed, since withdrawing
    /// the permission stops the session first.
    @Test
    func targetCommandsRunWhileNotAllowedAndOff() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)
        harness.service.setSessionsAllowed(false)
        harness.service.drain()
        harness.emitted.clear()

        harness.perform(.setDuration(minutes: 75))
        #expect(harness.service.state.nextTarget == .duration(minutes: 75))

        harness.perform(.setMode(.indefinite))
        #expect(harness.service.state.nextTarget == .indefinite)
        #expect(harness.assertions.calls.isEmpty)
    }

    @Test
    func aTargetCommandQueuedAfterSessionsAreDisallowedActsOnAStoppedSession() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.perform(.start)

        harness.service.setSessionsAllowed(false)
        harness.service.perform(.setDuration(minutes: 120))
        harness.service.drain()

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(!harness.assertions.calls.contains { if case .setTimeout = $0 { true } else { false } })
        #expect(harness.service.state.nextTarget == .duration(minutes: 120))
    }

    @Test
    func aRefusedRetimeKeepsTheEndAndTheTargetAndPublishesTheFailure() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.perform(.start)
        harness.assertions.refuseSetTimeout(.display, code: 12)
        harness.assertions.clearCalls()

        harness.perform(.setDuration(minutes: 45))

        let state = harness.service.state
        #expect(state.endsAt     == origin.addingTimeInterval(1800))
        #expect(state.nextTarget == .duration(minutes: 30))
        #expect(state.failure    == .extensionRefused(12))
        #expect(harness.assertions.liveCount == 2)
        #expect(harness.assertions.calls == [
            .setTimeout(.system, 2700),
            .setTimeout(.display, 2700),
            .setTimeout(.system, 1800),
        ])
        #expect(harness.preferences.lastDurationMinutes != 45)
    }

    // MARK: Display preference

    @Test
    func theDisplayToggleDuringASessionAcquiresOrReleasesOnlyTheDisplay() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.perform(.start)
        harness.clock.advance(by: 600)
        harness.assertions.clearCalls()

        harness.perform(.setKeepsDisplayAwake(false))

        #expect(harness.assertions.calls == [.release(.display)])
        #expect(harness.assertions.liveKinds == [.system])
        #expect(harness.service.state.keepsDisplayAwake == false)
        #expect(harness.preferences.keepsDisplayAwake   == false)

        harness.assertions.clearCalls()
        harness.perform(.setKeepsDisplayAwake(true))

        #expect(harness.assertions.calls == [.acquire(.display, 1200)])
        #expect(harness.assertions.liveKinds == [.system, .display])
        #expect(harness.service.state.keepsDisplayAwake == true)
    }

    @Test
    func theDisplayToggleWhileOffOnlyChangesThePreference() {
        let harness = CaffeinateHarness()

        harness.perform(.setKeepsDisplayAwake(false))

        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.service.state.keepsDisplayAwake == false)
        #expect(harness.emitted.count == 1)

        harness.perform(.start)
        #expect(harness.assertions.calls == [.acquire(.system, 3600)])
    }

    @Test
    func aRefusedDisplayAcquireKeepsThePreferenceAndSetsTheFailure() {
        let harness = CaffeinateHarness(keepsDisplayAwake: false)
        harness.perform(.start)
        harness.assertions.refuseAcquire(.display, code: 11)

        harness.perform(.setKeepsDisplayAwake(true))

        #expect(harness.service.state.keepsDisplayAwake == false)
        #expect(harness.service.state.failure == .assertionRefused(11))
        #expect(harness.service.state.isActive)
    }

    @Test
    func aGlyphChangeIsPublishedAndPersisted() {
        let harness = CaffeinateHarness()

        harness.perform(.setGlyph(.mug))

        #expect(harness.service.state.glyph == .mug)
        #expect(harness.preferences.glyph   == .mug)
        #expect(harness.emitted.count == 1)
    }

    // MARK: Failures

    @Test
    func aRefusedStartStaysOffAndPublishesTheFailure() {
        let harness = CaffeinateHarness()
        harness.assertions.refuseAcquire(.system, code: 5)

        harness.perform(.start)

        let state = harness.service.state
        #expect(!state.isActive)
        #expect(state.failure == .assertionRefused(5))
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.emitted.count == 1)
    }

    @Test
    func aRefusedDisplayAssertionRollsTheSystemAssertionBack() {
        let harness = CaffeinateHarness()
        harness.assertions.refuseAcquire(.display, code: 6)

        harness.perform(.start)

        #expect(!harness.service.state.isActive)
        #expect(harness.service.state.failure == .assertionRefused(6))
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.assertions.calls == [.acquire(.system, 3600), .acquire(.display, 3600), .release(.system)])
    }

    @Test
    func theNextCommandClearsTheFailure() {
        let harness = CaffeinateHarness()
        harness.assertions.refuseAcquire(.system)
        harness.perform(.start)
        #expect(harness.service.state.failure != nil)

        harness.assertions.allowEverything()
        harness.perform(.start)

        #expect(harness.service.state.failure == nil)
        #expect(harness.service.state.isActive)
    }

    @Test
    func aFailedReleaseKeepsTheIdentifierAndTheNextStopRetriesIt() {
        let harness = CaffeinateHarness()
        harness.perform(.start)
        harness.assertions.refuseRelease()

        harness.perform(.stop)

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 2)

        harness.assertions.allowEverything()
        harness.assertions.clearCalls()
        harness.perform(.stop)

        #expect(harness.assertions.calls == [.release(.system), .release(.display)])
        #expect(harness.assertions.liveCount == 0)
    }

    // MARK: Time

    @Test
    func expiryPublishesOffAndReleasesTheAssertions() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        harness.perform(.start)
        harness.emitted.clear()
        harness.clock.advance(by: 900)

        harness.service.expire()
        harness.service.drain()

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.emitted.count == 1)
        #expect(harness.emitted.all.last?.startedAt == nil)
    }

    @Test
    func expiryBeforeTheEndDoesNothing() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        harness.perform(.start)
        harness.emitted.clear()
        harness.clock.advance(by: 899)

        harness.service.expire()
        harness.service.drain()

        #expect(harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 2)
        #expect(harness.emitted.count == 0)
    }

    @Test
    func wakingPastTheEndPublishesOffButNotBeforeIt() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        harness.perform(.start)

        harness.clock.advance(by: 600)
        harness.service.systemDidWake()
        harness.service.drain()
        #expect(harness.service.state.isActive)

        harness.clock.advance(by: 600)
        harness.service.systemDidWake()
        harness.service.drain()
        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
    }

    @Test
    func expiryDoesNotEndAnIndefiniteSession() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)
        harness.perform(.start)
        harness.clock.advance(by: 10 * 86_400)

        harness.service.expire()
        harness.service.drain()

        #expect(harness.service.state.isActive)
    }

    @Test
    func theDeadlineTimerIsArmedOnlyWhileATimedSessionRuns() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        #expect(harness.service.armedDeadline == nil)

        harness.perform(.start)
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(900))

        harness.perform(.setDuration(minutes: 30))
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(1800))

        harness.perform(.setMode(.indefinite))
        #expect(harness.service.armedDeadline == nil)
        #expect(harness.service.state.endsAt == nil)

        harness.perform(.setDuration(minutes: 15))
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(900))

        harness.perform(.stop)
        #expect(harness.service.armedDeadline == nil)
    }

    @Test
    func theDeadlineTimerEndsTheSessionOnItsOwn() async throws {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        let start   = Date().addingTimeInterval(0.3 - 900)
        harness.clock.now = start
        harness.perform(.start)
        harness.clock.now = Date().addingTimeInterval(60)

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while harness.service.state.isActive, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.emitted.all.last?.startedAt == nil)
    }

    /// aToggleOnAJustExpiredSessionOnlyStops is the shortcut pressed inside the timer's leeway,
    /// or just after a wake: the user saw a session and asked to stop it.
    @Test
    func aToggleOnAJustExpiredSessionOnlyStops() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        harness.perform(.start)
        harness.clock.advance(by: 900.1)
        harness.emitted.clear()

        harness.perform(.toggle)

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.assertions.acquiredCount == 2)
        #expect(harness.emitted.count == 1)
        #expect(harness.emitted.all.last?.startedAt == nil)

        harness.perform(.toggle)
        #expect(harness.service.state.isActive)
    }

    @Test
    func aGestureRenewsTheActivityOnlyPastItsCap() {
        let harness = CaffeinateHarness(nextTarget: .indefinite)
        harness.perform(.start)

        harness.clock.advance(by: 7 * 3600)
        harness.perform(.setKeepsDisplayAwake(false))
        #expect(harness.service.state.activityStartedAt == origin)

        harness.clock.advance(by: 3600 + 1)
        harness.perform(.setKeepsDisplayAwake(true))
        #expect(harness.service.state.activityStartedAt == harness.clock.now)
        #expect(harness.service.state.startedAt         == origin)
    }

    // MARK: Emissions

    @Test
    func everyTransitionEmitsOnceAndANoOpEmitsNothing() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))

        harness.perform(.stop)
        harness.perform(.setKeepsDisplayAwake(true))
        #expect(harness.emitted.count == 0)

        harness.perform(.start)
        #expect(harness.emitted.count == 1)

        harness.perform(.start)
        #expect(harness.emitted.count == 1)

        harness.perform(.setDuration(minutes: 45))
        #expect(harness.emitted.count == 2)

        harness.perform(.setDuration(minutes: 45))
        #expect(harness.emitted.count == 2)

        harness.perform(.stop)
        #expect(harness.emitted.count == 3)
        #expect(harness.emitted.all.map(\.isActive) == [true, true, false])
    }

    @Test
    func aNewEmitterReceivesTheCurrentStateOnce() {
        let harness  = CaffeinateHarness()
        harness.perform(.start)
        let received = EmittedStates()

        harness.service.setEmitter { received.append($0) }
        harness.service.drain()

        #expect(received.count == 1)
        #expect(received.all.first?.isActive == true)
    }

    /// aSessionSurvivesTheEmitterGoingAway is a PluginHost loss: the kernel ends the source's
    /// lease, which takes the emitter away, and the session must go on; the next emitter, when
    /// the host is back, catches up with the session as it is.
    @Test
    func aSessionSurvivesTheEmitterGoingAway() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.perform(.start)
        harness.emitted.clear()

        harness.service.setEmitter(nil)
        harness.service.drain()

        #expect(harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 2)
        #expect(harness.assertions.releasedCount == 0)
        #expect(harness.emitted.count == 0)

        harness.perform(.setDuration(minutes: 45))
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(2700))
        #expect(harness.emitted.count == 0)

        let received = EmittedStates()
        harness.service.setEmitter { received.append($0) }
        harness.service.drain()

        #expect(received.count == 1)
        #expect(received.all.first?.isActive == true)
        #expect(received.all.first?.endsAt == origin.addingTimeInterval(2700))
    }

    @Test
    func disallowingSessionsStopsTheSessionAndEmitsOff() {
        let harness = CaffeinateHarness()
        harness.perform(.start)
        harness.emitted.clear()

        harness.service.setSessionsAllowed(false)
        harness.service.drain()

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.assertions.acquiredCount == harness.assertions.releasedCount)
        #expect(harness.emitted.count == 1)
        #expect(harness.emitted.all.last?.startedAt == nil)
        #expect(harness.service.armedDeadline == nil)
    }

    @Test
    func sessionCommandsAreIgnoredWhileNotAllowed() {
        let harness = CaffeinateHarness()
        harness.service.setSessionsAllowed(false)
        harness.service.drain()
        harness.emitted.clear()

        for command in [CaffeinateCommand.start, .toggle, .stop] {
            harness.service.perform(command)
        }
        harness.service.drain()

        #expect(harness.assertions.calls.isEmpty)
        #expect(!harness.service.state.isActive)
        #expect(harness.service.state.nextTarget == .duration(minutes: 60))
        #expect(harness.emitted.count == 0)

        harness.service.setSessionsAllowed(true)
        harness.perform(.start)
        #expect(harness.service.state.isActive)
    }

    @Test
    func sessionsStartOutNotAllowed() {
        let assertions = FakeAssertions()
        let service    = CaffeinateService(
            assertions : assertions,
            preferences: InMemoryCaffeinatePreferences(),
            now        : { TestClock.origin }
        )
        service.setEmitter { _ in }

        service.perform(.start)
        service.drain()

        #expect(assertions.calls.isEmpty)
        #expect(!service.state.isActive)
    }

    @Test
    func preferenceCommandsRunWhileNotAllowed() {
        let assertions  = FakeAssertions()
        let preferences = InMemoryCaffeinatePreferences()
        let service     = CaffeinateService(
            assertions : assertions,
            preferences: preferences,
            now        : { TestClock.origin }
        )

        service.perform(.setGlyph(.pill))
        service.perform(.setKeepsDisplayAwake(false))
        service.perform(.start)
        service.drain()

        #expect(service.state.glyph == .pill)
        #expect(!service.state.keepsDisplayAwake)
        #expect(preferences.glyph == .pill)
        #expect(!preferences.keepsDisplayAwake)
        #expect(!service.state.isActive)
        #expect(assertions.calls.isEmpty)
    }

    @Test
    func aToggleQueuedAfterSessionsAreDisallowedStartsNothing() {
        let harness = CaffeinateHarness()
        harness.perform(.start)

        harness.service.setSessionsAllowed(false)
        harness.service.perform(.toggle)
        harness.service.drain()

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.assertions.acquiredCount == harness.assertions.releasedCount)
    }

    @Test
    func sessionsAreAllowedOnlyWhileCaffeinateIsActive() throws {
        let other = try #require(PluginID(rawValue: "com.cascade.clock"))

        #expect(CaffeinateCommand.sessionsAllowed(in: [CaffeinateCommand.plugin: .active]))
        #expect(!CaffeinateCommand.sessionsAllowed(in: [CaffeinateCommand.plugin: .switchedOff]))
        #expect(!CaffeinateCommand.sessionsAllowed(in: [CaffeinateCommand.plugin: .quarantined]))
        #expect(!CaffeinateCommand.sessionsAllowed(in: [CaffeinateCommand.plugin: .disabledAfterHang]))
        #expect(!CaffeinateCommand.sessionsAllowed(in: [other: .active]))
        #expect(!CaffeinateCommand.sessionsAllowed(in: [:]))
    }

    @Test
    func systemClockDidChangeRechecksTheDeadline() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 15))
        harness.perform(.start)
        harness.clock.advance(by: 901)

        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        harness.service.drain()

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.emitted.all.last?.startedAt == nil)
    }

    // MARK: Preferences

    @Test
    func preferencesAreReadOnceAndWrittenOnlyOnChange() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        #expect(harness.service.state.nextTarget == .duration(minutes: 30))
        let baseline = harness.preferences.writes

        harness.perform(.start)
        harness.perform(.stop)
        harness.perform(.setKeepsDisplayAwake(true))
        #expect(harness.preferences.writes == baseline)

        // The target and the last duration both change.
        harness.perform(.setDuration(minutes: 45))
        #expect(harness.preferences.writes == baseline + 2)
        #expect(harness.preferences.nextTarget == .duration(minutes: 45))

        harness.perform(.setDuration(minutes: 45))
        #expect(harness.preferences.writes == baseline + 2)
    }

    @Test
    func userDefaultsPreferencesStartWithDefaultsAndRoundTrip() throws {
        let suite = "CaffeinateServiceTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsCaffeinatePreferences(defaults: store)
        #expect(preferences.nextTarget           == .indefinite)
        #expect(preferences.lastDurationMinutes  == nil)
        #expect(preferences.lastUntilMinuteOfDay == nil)
        #expect(preferences.keepsDisplayAwake    == true)
        #expect(preferences.glyph                == .cupHeatWaves)

        preferences.nextTarget           = .until(minuteOfDay: 1080)
        preferences.lastDurationMinutes  = 90
        preferences.lastUntilMinuteOfDay = 1080
        preferences.keepsDisplayAwake    = false
        preferences.glyph                = .pill

        let reread = UserDefaultsCaffeinatePreferences(defaults: store)
        #expect(reread.nextTarget           == .until(minuteOfDay: 1080))
        #expect(reread.lastDurationMinutes  == 90)
        #expect(reread.lastUntilMinuteOfDay == 1080)
        #expect(reread.keepsDisplayAwake    == false)
        #expect(reread.glyph                == .pill)

        for target: CaffeinateTarget in [.indefinite, .duration(minutes: 15), .duration(minutes: 1440), .until(minuteOfDay: 0)] {
            preferences.nextTarget = target
            #expect(UserDefaultsCaffeinatePreferences(defaults: store).nextTarget == target)
        }
    }

    @Test
    func userDefaultsPreferencesIgnoreValuesOffTheScale() throws {
        let suite = "CaffeinateServiceTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        store.set("duration", forKey: "caffeinate.nextTarget.kind")
        store.set(7, forKey: "caffeinate.nextTarget.value")
        store.set(7, forKey: "caffeinate.lastDuration")
        store.set(1440, forKey: "caffeinate.lastUntil")
        store.set("nonsense", forKey: "caffeinate.glyph")

        let preferences = UserDefaultsCaffeinatePreferences(defaults: store)
        #expect(preferences.nextTarget           == .indefinite)
        #expect(preferences.lastDurationMinutes  == nil)
        #expect(preferences.lastUntilMinuteOfDay == nil)
        #expect(preferences.glyph                == .cupHeatWaves)

        store.set("forever", forKey: "caffeinate.nextTarget.kind")
        #expect(UserDefaultsCaffeinatePreferences(defaults: store).nextTarget == .indefinite)
    }

    @Test
    func theServiceReadsTheRememberedValuesFromThePreferences() {
        let preferences = InMemoryCaffeinatePreferences()
        preferences.nextTarget           = .indefinite
        preferences.lastDurationMinutes  = 150
        preferences.lastUntilMinuteOfDay = 1305
        let service = CaffeinateService(
            assertions : FakeAssertions(),
            preferences: preferences,
            now        : { TestClock.origin },
            calendar   : { CaffeinateHarness.utc }
        )

        service.perform(.setMode(.duration))
        service.drain()
        #expect(service.state.nextTarget == .duration(minutes: 150))

        service.perform(.setMode(.until))
        service.drain()
        #expect(service.state.nextTarget == .until(minuteOfDay: 1305))
    }

    // MARK: Concurrency

    @Test
    func concurrentCommandsNeverLeakAnAssertion() {
        let harness  = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        let commands: [CaffeinateCommand] = [.start, .stop, .toggle, .setDuration(minutes: 45), .setMode(.indefinite), .setMode(.until), .setKeepsDisplayAwake(false), .setKeepsDisplayAwake(true)]

        DispatchQueue.concurrentPerform(iterations: 4) { thread in
            for index in 0 ..< 50 {
                harness.service.perform(commands[(thread * 3 + index) % commands.count])
                if index % 10 == 0 { _ = harness.service.state }
            }
        }
        harness.service.drain()

        let assertions = harness.assertions
        #expect(assertions.acquiredCount == assertions.releasedCount + assertions.liveCount)
        let state = harness.service.state
        let expectedLive = state.isActive ? (state.keepsDisplayAwake ? 2 : 1) : 0
        #expect(assertions.liveCount == expectedLive)
        #expect(assertions.violations == 0)

        harness.perform(.stop)
        #expect(assertions.liveCount == 0)
    }

    @Test
    func noAssertionCallHappensWhileTheServiceLockIsHeld() {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))

        harness.perform(.start)
        harness.perform(.setDuration(minutes: 45))
        harness.perform(.setMode(.indefinite))
        harness.perform(.setUntil(origin.addingTimeInterval(3 * 3600)))
        harness.perform(.setKeepsDisplayAwake(false))
        harness.perform(.setKeepsDisplayAwake(true))
        harness.assertions.refuseSetTimeout(.display)
        harness.perform(.setDuration(minutes: 60))
        harness.assertions.allowEverything()
        harness.perform(.stop)

        #expect(!harness.assertions.calls.isEmpty)
        #expect(harness.assertions.violations == 0)
    }

    // MARK: Commands, source, IOKit

    @Test
    func actionsMapToCommands() throws {
        func command(_ action: String, _ value: PluginValue? = nil) throws -> CaffeinateCommand? {
            CaffeinateCommand(try PluginActionEvent(feature: "caffeinate", action: action, value: value))
        }

        #expect(try command("caffeinate.start")                == .start)
        #expect(try command("caffeinate.stop")                 == .stop)
        #expect(try command("caffeinate.extend")               == nil)
        #expect(try command("caffeinate.duration.up")          == nil)
        #expect(try command("caffeinate.duration.down")        == nil)
        #expect(try command("caffeinate.mode.indefinite")      == .setMode(.indefinite))
        #expect(try command("caffeinate.mode.duration")        == .setMode(.duration))
        #expect(try command("caffeinate.mode.until")           == .setMode(.until))
        #expect(try command("caffeinate.duration.set", .number(90)) == .setDuration(minutes: 90))
        #expect(try command("caffeinate.duration.set", .number(7))  == .setDuration(minutes: 7))
        #expect(try command("caffeinate.duration.set", .number(90.5)) == nil)
        #expect(try command("caffeinate.duration.set")              == nil)
        #expect(try command("caffeinate.until.set", .number(1_800_003_600)) == .setUntil(Date(timeIntervalSince1970: 1_800_003_600)))
        #expect(try command("caffeinate.until.set", .bool(true))    == nil)
        #expect(try command("caffeinate.until.set")                 == nil)
        #expect(try command("caffeinate.until.set", .number(1e300)) == nil)
        #expect(try command("caffeinate.display", .bool(false)) == .setKeepsDisplayAwake(false))
        #expect(try command("caffeinate.display")              == nil)
        #expect(try command("caffeinate.options")              == nil)
        #expect(CaffeinateCommand.plugin.rawValue == "com.cascade.caffeinate")
    }

    @Test
    func theSourceEmitsEveryTransitionUntilStoppedAndCatchesUpOnRestart() throws {
        let harness = CaffeinateHarness(nextTarget: .duration(minutes: 30))
        harness.service.setEmitter(nil)
        harness.service.drain()
        let events = Mutex<[PluginSourceEvent]>([])
        let source = CaffeinatePluginSource(service: harness.service)

        source.start { event in events.withLock { $0.append(event) } }
        harness.service.drain()
        #expect(events.withLock { $0.count } == 1)

        harness.perform(.start)
        #expect(events.withLock { $0.count } == 2)
        let last = try #require(events.withLock { $0.last })
        let state = try #require(PluginCaffeinateState(last))
        #expect(state.isActive)
        #expect(state.endsAt == origin.addingTimeInterval(1800))

        source.stop()
        harness.service.drain()
        #expect(harness.service.state.isActive)

        harness.perform(.setDuration(minutes: 45))
        #expect(events.withLock { $0.count } == 2)

        source.start { event in events.withLock { $0.append(event) } }
        harness.service.drain()
        #expect(events.withLock { $0.count } == 3)
        let latest   = try #require(events.withLock { $0.last })
        let caughtUp = try #require(PluginCaffeinateState(latest))
        #expect(caughtUp.endsAt == origin.addingTimeInterval(2700))
    }

    @Test
    func theIOKitAssertionsAcquireRetimeAndRelease() throws {
        let assertions = IOKitCaffeinateAssertions()

        let identifier = try assertions.acquire(.system, timeout: 30)
        try assertions.setTimeout(nil, of: identifier)
        try assertions.setTimeout(60, of: identifier)
        try assertions.release(identifier)

        #expect(throws: CaffeinateAssertionError.self) { try assertions.release(identifier) }
    }
}
