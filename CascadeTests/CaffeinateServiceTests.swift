//
//  CaffeinateServiceTests.swift
//  CascadeTests
//

import CascadeContracts
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

        var nextDuration     : CaffeinateDuration = .minutes(60)
        var keepsDisplayAwake: Bool               = true
        var glyph            : CaffeinateGlyph    = .cupHeatWaves
        var writes           : Int                = 0
    }

    private let values = Mutex(Values())

    var writes: Int { values.withLock { $0.writes } }

    var nextDuration: CaffeinateDuration {
        get { values.withLock { $0.nextDuration } }
        set { values.withLock { $0.nextDuration = newValue; $0.writes += 1 } }
    }

    var keepsDisplayAwake: Bool {
        get { values.withLock { $0.keepsDisplayAwake } }
        set { values.withLock { $0.keepsDisplayAwake = newValue; $0.writes += 1 } }
    }

    var glyph: CaffeinateGlyph {
        get { values.withLock { $0.glyph } }
        set { values.withLock { $0.glyph = newValue; $0.writes += 1 } }
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

    /// init builds a service with an emitter already set and the initial snapshot forgotten, so
    /// a test counts only the transitions it causes.
    init(
        nextDuration     : CaffeinateDuration = .minutes(60),
        keepsDisplayAwake: Bool               = true
    ) {
        let assertions  = FakeAssertions()
        let preferences = InMemoryCaffeinatePreferences()
        let clock       = TestClock()
        let emitted     = EmittedStates()

        preferences.nextDuration      = nextDuration
        preferences.keepsDisplayAwake = keepsDisplayAwake
        let service = CaffeinateService(
            assertions : assertions,
            preferences: preferences,
            now        : { clock.now }
        )
        assertions.watch(service)
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
        let harness = CaffeinateHarness(nextDuration: .minutes(30))

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
        let harness = CaffeinateHarness(nextDuration: .indefinite)

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
        #expect(state.nextDuration      == .minutes(60))
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

    // MARK: Extend

    @Test
    func extendMovesBothTimeoutsAndTheEndByFifteenMinutes() {
        let harness = CaffeinateHarness(nextDuration: .minutes(30))
        harness.perform(.start)
        harness.clock.advance(by: 300)
        harness.assertions.clearCalls()

        harness.perform(.extend)

        let remaining: TimeInterval = 1800 + 900 - 300
        #expect(harness.assertions.calls == [.setTimeout(.system, remaining), .setTimeout(.display, remaining)])
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(2700))
        #expect(harness.service.state.startedAt == origin)
    }

    @Test
    func extendIsANoOpWhileOffOrIndefinite() {
        let harness = CaffeinateHarness(nextDuration: .indefinite)

        harness.perform(.extend)
        #expect(harness.emitted.count == 0)

        harness.perform(.start)
        harness.assertions.clearCalls()
        harness.emitted.clear()
        harness.perform(.extend)

        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.emitted.count == 0)
    }

    @Test
    func extendAfterExpiryDoesNothing() {
        let harness = CaffeinateHarness(nextDuration: .minutes(15))
        harness.perform(.start)
        harness.clock.advance(by: 901)
        harness.assertions.clearCalls()

        harness.perform(.extend)

        #expect(!harness.assertions.calls.contains { if case .setTimeout = $0 { true } else { false } })
        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.emitted.all.last?.startedAt == nil)
    }

    @Test
    func extendNeverLetsTheSessionPassTwentyFourHours() {
        let harness = CaffeinateHarness(nextDuration: .minutes(1440))
        harness.perform(.start)
        harness.assertions.clearCalls()

        harness.perform(.extend)

        #expect(harness.assertions.calls.isEmpty)
        #expect(harness.service.state.endsAt == origin.addingTimeInterval(86_400))

        harness.clock.advance(by: 600)
        harness.perform(.extend)

        #expect(harness.service.state.endsAt == origin.addingTimeInterval(86_400 + 600))
        #expect(harness.assertions.calls == [.setTimeout(.system, 86_400), .setTimeout(.display, 86_400)])
    }

    // MARK: Steps

    @Test
    func stepsWhileOffMoveTheNextDurationAndPersistIt() {
        let harness = CaffeinateHarness(nextDuration: .minutes(60))

        harness.perform(.stepUp)
        #expect(harness.service.state.nextDuration == .minutes(75))
        #expect(harness.preferences.nextDuration   == .minutes(75))

        harness.perform(.stepDown)
        harness.perform(.stepDown)
        #expect(harness.service.state.nextDuration == .minutes(45))
        #expect(harness.assertions.calls.isEmpty)
    }

    @Test
    func aStepAtTheEdgeOfTheScaleDoesNothing() {
        let harness = CaffeinateHarness(nextDuration: .indefinite)

        harness.perform(.stepDown)

        #expect(harness.service.state.nextDuration == .indefinite)
        #expect(harness.emitted.count == 0)
    }

    @Test
    func stepWhileActiveUsesTimeLeftRoundedUp() {
        let harness = CaffeinateHarness(nextDuration: .minutes(60))
        harness.perform(.start)
        harness.clock.advance(by: 50 * 60)
        harness.assertions.clearCalls()

        harness.perform(.stepDown)

        #expect(harness.service.state.endsAt       == nil)
        #expect(harness.service.state.startedAt    == origin)
        #expect(harness.service.state.nextDuration == .indefinite)
        #expect(harness.assertions.calls == [.setTimeout(.system, nil), .setTimeout(.display, nil)])

        harness.clock.advance(by: 3600)
        harness.perform(.stepUp)

        #expect(harness.service.state.endsAt       == harness.clock.now.addingTimeInterval(900))
        #expect(harness.service.state.nextDuration == .minutes(15))
    }

    @Test
    func stepUpWithTenMinutesLeftGoesToThirty() {
        let harness = CaffeinateHarness(nextDuration: .minutes(60))
        harness.perform(.start)
        harness.clock.advance(by: 50 * 60)
        harness.assertions.clearCalls()

        harness.perform(.stepUp)

        #expect(harness.service.state.endsAt       == harness.clock.now.addingTimeInterval(1800))
        #expect(harness.service.state.nextDuration == .minutes(30))
        #expect(harness.assertions.calls == [.setTimeout(.system, 1800), .setTimeout(.display, 1800)])
        #expect(harness.assertions.acquiredCount == 2)
        #expect(harness.assertions.releasedCount == 0)
    }

    // MARK: Display preference

    @Test
    func theDisplayToggleDuringASessionAcquiresOrReleasesOnlyTheDisplay() {
        let harness = CaffeinateHarness(nextDuration: .minutes(30))
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
    func aRefusedExtensionKeepsTheSessionAndItsEndAndPublishesTheFailure() {
        let harness = CaffeinateHarness(nextDuration: .minutes(30))
        harness.perform(.start)
        harness.assertions.refuseSetTimeout(.display, code: 12)
        harness.assertions.clearCalls()

        harness.perform(.extend)

        let state = harness.service.state
        #expect(state.endsAt  == origin.addingTimeInterval(1800))
        #expect(state.failure == .extensionRefused(12))
        #expect(harness.assertions.liveCount == 2)
        #expect(harness.assertions.calls == [
            .setTimeout(.system, 2700),
            .setTimeout(.display, 2700),
            .setTimeout(.system, 1800),
        ])
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
        let harness = CaffeinateHarness(nextDuration: .minutes(15))
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
        let harness = CaffeinateHarness(nextDuration: .minutes(15))
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
        let harness = CaffeinateHarness(nextDuration: .minutes(15))
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
        let harness = CaffeinateHarness(nextDuration: .indefinite)
        harness.perform(.start)
        harness.clock.advance(by: 10 * 86_400)

        harness.service.expire()
        harness.service.drain()

        #expect(harness.service.state.isActive)
    }

    @Test
    func theDeadlineTimerIsArmedOnlyWhileATimedSessionRuns() {
        let harness = CaffeinateHarness(nextDuration: .minutes(15))
        #expect(harness.service.armedDeadline == nil)

        harness.perform(.start)
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(900))

        harness.perform(.extend)
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(1800))

        harness.perform(.stepDown)
        harness.perform(.stepDown)
        #expect(harness.service.armedDeadline == nil)
        #expect(harness.service.state.endsAt == nil)

        harness.perform(.stepUp)
        #expect(harness.service.armedDeadline == origin.addingTimeInterval(900))

        harness.perform(.stop)
        #expect(harness.service.armedDeadline == nil)
    }

    @Test
    func theDeadlineTimerEndsTheSessionOnItsOwn() async throws {
        let harness = CaffeinateHarness(nextDuration: .minutes(15))
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

    @Test
    func aGestureRenewsTheActivityOnlyPastItsCap() {
        let harness = CaffeinateHarness(nextDuration: .indefinite)
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
        let harness = CaffeinateHarness(nextDuration: .minutes(30))

        harness.perform(.stop)
        harness.perform(.extend)
        harness.perform(.setKeepsDisplayAwake(true))
        #expect(harness.emitted.count == 0)

        harness.perform(.start)
        #expect(harness.emitted.count == 1)

        harness.perform(.start)
        #expect(harness.emitted.count == 1)

        harness.perform(.extend)
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

    @Test
    func endingTheLeaseStopsTheSessionAndSilencesTheEmitter() {
        let harness = CaffeinateHarness()
        harness.perform(.start)
        harness.emitted.clear()

        harness.service.setEmitter(nil)
        harness.service.drain()

        #expect(!harness.service.state.isActive)
        #expect(harness.assertions.liveCount == 0)
        #expect(harness.emitted.count == 0)

        harness.perform(.start)
        #expect(harness.emitted.count == 0)
        #expect(harness.service.state.isActive)
    }

    // MARK: Preferences

    @Test
    func preferencesAreReadOnceAndWrittenOnlyOnChange() {
        let harness = CaffeinateHarness(nextDuration: .minutes(30))
        #expect(harness.service.state.nextDuration == .minutes(30))
        let baseline = harness.preferences.writes

        harness.perform(.start)
        harness.perform(.extend)
        harness.perform(.stop)
        harness.perform(.setKeepsDisplayAwake(true))
        #expect(harness.preferences.writes == baseline)

        harness.perform(.stepUp)
        #expect(harness.preferences.writes == baseline + 1)
    }

    @Test
    func userDefaultsPreferencesStartWithDefaultsAndRoundTrip() throws {
        let suite = "CaffeinateServiceTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsCaffeinatePreferences(defaults: store)
        #expect(preferences.nextDuration      == .minutes(60))
        #expect(preferences.keepsDisplayAwake == true)
        #expect(preferences.glyph             == .cupHeatWaves)

        preferences.nextDuration      = .indefinite
        preferences.keepsDisplayAwake = false
        preferences.glyph             = .pill

        let reread = UserDefaultsCaffeinatePreferences(defaults: store)
        #expect(reread.nextDuration      == .indefinite)
        #expect(reread.keepsDisplayAwake == false)
        #expect(reread.glyph             == .pill)
        #expect(store.integer(forKey: "caffeinate.nextDuration") == 0)
    }

    @Test
    func userDefaultsPreferencesIgnoreValuesOffTheScale() throws {
        let suite = "CaffeinateServiceTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        store.set(7, forKey: "caffeinate.nextDuration")
        store.set("nonsense", forKey: "caffeinate.glyph")

        let preferences = UserDefaultsCaffeinatePreferences(defaults: store)
        #expect(preferences.nextDuration == .minutes(60))
        #expect(preferences.glyph        == .cupHeatWaves)
    }

    // MARK: Concurrency

    @Test
    func concurrentCommandsNeverLeakAnAssertion() {
        let harness  = CaffeinateHarness(nextDuration: .minutes(30))
        let commands: [CaffeinateCommand] = [.start, .extend, .stop, .toggle, .stepUp, .setKeepsDisplayAwake(false), .setKeepsDisplayAwake(true)]

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
        let harness = CaffeinateHarness(nextDuration: .minutes(30))

        harness.perform(.start)
        harness.perform(.extend)
        harness.perform(.stepDown)
        harness.perform(.setKeepsDisplayAwake(false))
        harness.perform(.setKeepsDisplayAwake(true))
        harness.assertions.refuseSetTimeout(.display)
        harness.perform(.extend)
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
        #expect(try command("caffeinate.extend")               == .extend)
        #expect(try command("caffeinate.duration.up")          == .stepUp)
        #expect(try command("caffeinate.duration.down")        == .stepDown)
        #expect(try command("caffeinate.display", .bool(false)) == .setKeepsDisplayAwake(false))
        #expect(try command("caffeinate.display")              == nil)
        #expect(try command("caffeinate.options")              == nil)
        #expect(CaffeinateCommand.plugin.rawValue == "com.cascade.caffeinate")
    }

    @Test
    func theSourceEmitsTheCurrentStateOnStartAndEveryTransitionUntilStopped() throws {
        let harness = CaffeinateHarness(nextDuration: .minutes(30))
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
        #expect(!harness.service.state.isActive)
        #expect(events.withLock { $0.count } == 2)
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
