//
//  AppAudioServiceTests.swift
//  CascadeTests
//

import CascadeContracts
import Foundation
import Testing
@testable import Cascade

@MainActor
struct AppAudioServiceTests {

    /// Fixture is one service wired to a fake connection, a manual clock and scheduler, and a
    /// private `UserDefaults` suite, with the statuses and snapshots it delivered on main.
    @MainActor
    private final class Fixture {

        let connection = FakeAudioHostConnection()
        let scheduler  = ManualAudioScheduler()
        let clock      = ManualAudioClock()
        let queue      = DispatchQueue(label: "CascadeTests.AppAudio")
        let suiteName  = "CascadeTests.AppAudio." + UUID().uuidString
        let defaults   : UserDefaults
        let store      : AudioIntentStore

        private(set) var statuses : [AudioHostStatus] = []
        private(set) var snapshots: [AudioHostSnapshot] = []
        private(set) var service  : AppAudioService?

        init(storedIntents: [AudioAppIdentity: AudioAppIntent] = [:]) {
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard

            self.defaults = defaults
            self.store    = AudioIntentStore(defaults: defaults)

            store.save(storedIntents)
        }

        /// start builds the service, which reads the store and may connect at once.
        @discardableResult
        func start() -> AppAudioService {
            let clock     = clock
            let scheduler = scheduler
            let service   = AppAudioService(
                connection: connection,
                store     : store,
                queue     : queue,
                clock     : { clock.read() },
                schedule  : { delay, work in scheduler.schedule(delay, work) }
            )

            service.onStatus   = { [weak self] in self?.statuses.append($0) }
            service.onSnapshot = { [weak self] in self?.snapshots.append($0) }
            self.service       = service

            return service
        }

        /// settle waits for everything the service queued: the queue first, repeatedly because
        /// a fake reply posts more work onto it, then the main-queue hop that deliveries take.
        /// Neither wait is a sleep.
        func settle() async {
            for _ in 0..<4 {
                queue.sync {}
            }

            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private static func identity(_ bundleID: String) throws -> AudioAppIdentity {
        try AudioAppIdentity(bundleID: bundleID)
    }

    private static func intent(
        gain      : Double = 0.5,
        isMuted   : Bool = false,
        outputUIDs: [String] = []
    ) throws -> AudioAppIntent {
        try AudioAppIntent(gain: gain, isMuted: isMuted, outputUIDs: outputUIDs)
    }

    // MARK: - Connecting

    @Test
    func connectReplaysStoredIntents() async throws {
        let music    = try Self.identity("com.apple.Music")
        let stored   = [music: try Self.intent(gain: 0.3)]
        let fixture  = Fixture(storedIntents: stored)
        defer { fixture.tearDown() }

        fixture.start()
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == 1)
        #expect(fixture.connection.read { $0.helloCount } == 1)
        #expect(fixture.connection.read { $0.sent } == [.replaceIntents(stored)])
        #expect(fixture.statuses == [.running])
    }

    @Test
    func neutralIntentsAndHiddenMixerStopAudioHost() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == 0)

        service.setMixerVisible(true)
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == 1)
        #expect(fixture.statuses == [.running])

        let sentWhileVisible = fixture.connection.read { $0.sent.count }
        service.setMixerVisible(false)
        await fixture.settle()

        #expect(fixture.connection.read { $0.disconnectCount } == 1)
        #expect(fixture.connection.read { $0.sent.count } == sentWhileVisible)
        #expect(fixture.statuses == [.running, .idle])

        service.setIntent(try Self.intent(gain: 0.2), for: music)
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == 2)
        #expect(fixture.connection.read { $0.sent.last } == .replaceIntents([music: try Self.intent(gain: 0.2)]))

        service.returnToNative(music)
        await fixture.settle()

        #expect(fixture.connection.read { $0.sent.last } == .returnToNative(music))
        #expect(fixture.connection.read { $0.disconnectCount } == 2)
        #expect(fixture.store.load().isEmpty)
        #expect(fixture.statuses.last == .idle)
    }

    @Test
    func aVisibleMixerKeepsAudioHostEvenWhenEveryIntentIsNeutral() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent(gain: 0.4)])
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        service.returnToNative(music)
        await fixture.settle()

        #expect(fixture.connection.read { $0.disconnectCount } == 0)
        #expect(fixture.connection.read { $0.sent.last } == .returnToNative(music))
    }

    @Test
    func setIntentStoresSavesAndSends() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        let intent = try Self.intent(gain: 0.6, isMuted: true)
        service.setIntent(intent, for: music)
        await fixture.settle()

        #expect(fixture.connection.read { $0.sent.last } == .setIntent(music, intent))
        #expect(fixture.store.load() == [music: intent])
    }

    @Test
    func snapshotsReachTheModelOnMainAndStaleOnesAreDropped() async throws {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        let snapshot = try AudioHostSnapshot(generation: 1, apps: [], captureAllowed: true)
        fixture.connection.publish(snapshot)
        await fixture.settle()

        #expect(fixture.snapshots == [snapshot])

        let staleSnapshot = try AudioHostSnapshot(generation: 2, apps: [], captureAllowed: true)
        let staleDelivery = fixture.connection.read { $0.onSnapshot }

        fixture.connection.crash()
        await fixture.settle()
        staleDelivery?(staleSnapshot)
        await fixture.settle()

        #expect(fixture.snapshots == [snapshot])
    }

    // MARK: - Supervision

    @Test
    func commandWithoutReplyKillsAfterThreeSeconds() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        fixture.connection.edit { $0.repliesAutomatically = false }
        fixture.clock.advance(by: .seconds(1))
        service.setIntent(try Self.intent(), for: music)
        await fixture.settle()

        // The timer armed at connect fires at second 3 and finds the command only 2 seconds old.
        fixture.clock.advance(by: .seconds(2))
        fixture.scheduler.fireAll()
        await fixture.settle()

        #expect(fixture.connection.read { $0.killCount } == 0)
        #expect(fixture.scheduler.delays.last == .seconds(1))

        fixture.clock.advance(by: .seconds(1))
        fixture.scheduler.fireAll()
        await fixture.settle()

        #expect(fixture.connection.read { $0.killCount } == 1)
        #expect(fixture.connection.read { $0.disconnectCount } == 1)
        #expect(fixture.statuses.last == .recovering)
        #expect(fixture.scheduler.delays.last == .seconds(1))
    }

    @Test
    func aReplyBeforeTheDeadlineKeepsAudioHost() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        service.setIntent(try Self.intent(), for: music)
        await fixture.settle()

        fixture.clock.advance(by: .seconds(10))
        fixture.scheduler.fireAll()
        await fixture.settle()

        #expect(fixture.connection.read { $0.killCount } == 0)
        #expect(fixture.statuses == [.running])
    }

    @Test
    func footprintOverLimitKills() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        fixture.connection.edit { $0.footprint = AudioHostSupervision.memoryLimit + 1 }
        service.setIntent(try Self.intent(), for: music)
        await fixture.settle()

        #expect(fixture.connection.read { $0.killCount } == 1)
        #expect(fixture.statuses.last == .recovering)
    }

    @Test
    func footprintUnderLimitDoesNotKill() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture()
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        await fixture.settle()

        fixture.connection.edit { $0.footprint = AudioHostSupervision.memoryLimit }
        service.setIntent(try Self.intent(), for: music)
        await fixture.settle()

        #expect(fixture.connection.read { $0.killCount } == 0)
    }

    @Test
    func crashRestartsAfterBackoffAndReplays() async throws {
        let music   = try Self.identity("com.apple.Music")
        let safari  = try Self.identity("com.apple.Safari")
        let fixture = Fixture(storedIntents: [music: try Self.intent(gain: 0.3)])
        defer { fixture.tearDown() }

        fixture.start()
        await fixture.settle()

        fixture.connection.crash()
        await fixture.settle()

        #expect(fixture.statuses == [.running, .recovering])
        #expect(fixture.scheduler.delays.last == .seconds(1))
        #expect(fixture.connection.read { $0.connectCount } == 1)

        // A change made while AudioHost is down is stored and replayed, not lost.
        fixture.service?.setIntent(try Self.intent(gain: 0.8), for: safari)
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == 1)

        fixture.scheduler.fireAll()
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == 2)
        #expect(
            fixture.connection.read { $0.sent.last }
                == .replaceIntents([music: try Self.intent(gain: 0.3), safari: try Self.intent(gain: 0.8)])
        )
        #expect(fixture.statuses == [.running, .recovering, .running])
    }

    @Test
    func threeFaultsInFiveMinutesGiveUp() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent()])
        defer { fixture.tearDown() }

        fixture.start()
        await fixture.settle()

        for _ in 0..<2 {
            fixture.connection.crash()
            await fixture.settle()
            fixture.scheduler.fireAll()
            await fixture.settle()
        }

        #expect(fixture.connection.read { $0.connectCount } == 3)
        #expect(fixture.scheduler.delays.filter { $0 != AudioHostSupervision.commandDeadline } == [.seconds(1), .seconds(5)])

        fixture.connection.crash()
        await fixture.settle()
        fixture.scheduler.fireAll()
        await fixture.settle()

        #expect(fixture.statuses.last == .givenUp)
        #expect(fixture.connection.read { $0.connectCount } == 3)
        #expect(fixture.scheduler.unfiredCount == 0)
    }

    @Test
    func faultsMoreThanFiveMinutesApartNeverGiveUp() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent()])
        defer { fixture.tearDown() }

        fixture.start()
        await fixture.settle()

        for _ in 0..<5 {
            fixture.clock.advance(by: .seconds(301))
            fixture.connection.crash()
            await fixture.settle()
            fixture.scheduler.fireAll()
            await fixture.settle()
        }

        #expect(fixture.statuses.last == .running)
        #expect(fixture.connection.read { $0.connectCount } == 6)
    }

    @Test
    func restartForgivesAndReconnects() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent()])
        defer { fixture.tearDown() }

        let service = fixture.start()
        await fixture.settle()

        for _ in 0..<3 {
            fixture.connection.crash()
            await fixture.settle()
            fixture.scheduler.fireAll()
            await fixture.settle()
        }

        #expect(fixture.statuses.last == .givenUp)

        let connectsBeforeRestart = fixture.connection.read { $0.connectCount }
        service.restart()
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } == connectsBeforeRestart + 1)
        #expect(fixture.statuses.last == .running)

        // The history is clean: one more crash backs off by a second, it does not give up.
        fixture.connection.crash()
        await fixture.settle()

        #expect(fixture.statuses.last == .recovering)
        #expect(fixture.scheduler.delays.last == .seconds(1))
    }

    @Test
    func aRefusedConnectionCountsAsACrash() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent()])
        defer { fixture.tearDown() }

        fixture.connection.edit { $0.refusesConnect = true }
        fixture.start()
        await fixture.settle()

        #expect(fixture.statuses == [.recovering])
        #expect(fixture.scheduler.delays.last == .seconds(1))
    }

    @Test
    func aHandshakeWithTheWrongPeerCountsAsACrash() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent()])
        defer { fixture.tearDown() }

        fixture.connection.edit { $0.helloPID = nil }
        fixture.start()
        await fixture.settle()

        #expect(fixture.statuses == [.recovering])
        #expect(fixture.connection.read { $0.sent.isEmpty })
    }

    // MARK: - Intents

    @Test
    func intentsSurviveAMissingDevice() async throws {
        let music    = try Self.identity("com.apple.Music")
        let intent   = try Self.intent(gain: 0.7, outputUIDs: ["unplugged-headphones"])
        let fixture  = Fixture(storedIntents: [music: intent])
        defer { fixture.tearDown() }

        fixture.start()
        await fixture.settle()

        let notApplied = try AudioAppSnapshot(
            identity           : music,
            displayName        : "Music",
            intent             : intent,
            enforcement        : .notApplied,
            effectiveOutputUIDs: []
        )
        fixture.connection.publish(try AudioHostSnapshot(generation: 1, apps: [notApplied], captureAllowed: true))
        await fixture.settle()

        #expect(fixture.store.load() == [music: intent])

        fixture.connection.crash()
        await fixture.settle()
        fixture.scheduler.fireAll()
        await fixture.settle()

        #expect(fixture.connection.read { $0.sent.last } == .replaceIntents([music: intent]))
    }

    // MARK: - Threads

    @Test
    func noXPCCallOnTheMainThread() async throws {
        let music   = try Self.identity("com.apple.Music")
        let fixture = Fixture(storedIntents: [music: try Self.intent()])
        defer { fixture.tearDown() }

        let service = fixture.start()
        service.setMixerVisible(true)
        service.setIntent(try Self.intent(gain: 0.9), for: music)
        await fixture.settle()

        fixture.connection.edit { $0.footprint = 1 << 20 }
        service.returnToNative(music)
        service.setMixerVisible(false)
        await fixture.settle()

        fixture.connection.crash()
        service.setMixerVisible(true)
        await fixture.settle()
        fixture.scheduler.fireAll()
        service.restart()
        await fixture.settle()

        #expect(fixture.connection.read { $0.connectCount } >= 2)
        #expect(fixture.connection.read { $0.mainThreadCalls } == 0)
    }
}
