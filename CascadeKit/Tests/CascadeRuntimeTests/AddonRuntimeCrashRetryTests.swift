//
//  AddonRuntimeCrashRetryTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonRuntimeCrashRetryTests {

    @Test
    func classifiedPremetricCrashWithCanonicalInterestRetriesAtCommonDeadline() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 0)

        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 1)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == true)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(1))
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.requestLaunch(owner: fixture.providerID)
        }

        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 1)

        fixture.advance(1)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 2)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
        let replacement = try #require(fixture.adapter.lastStart(owner: fixture.providerID))
        await fixture.runtime.observeExit(replacement.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 2)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(5))

        fixture.advance(5)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 3)
        let third = try #require(fixture.adapter.lastStart(owner: fixture.providerID))
        await fixture.runtime.observeExit(third.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 3)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(30))

        fixture.advance(30)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 4)
        let fourth = try #require(fixture.adapter.lastStart(owner: fixture.providerID))
        await fixture.runtime.observeExit(fourth.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.isQuarantined == true)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.requestLaunch(owner: fixture.providerID)
        }

        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 4)
    }

    @Test
    func unclassifiedAndUndemandedExitsDoNotCreateRetry() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.observeExit(fixture.provider.incarnation)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 0)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)

        let solo    = try installedFixture("focus", publisher: "TEST-ONLY.solo")
        let clock   = MutableRuntimeClock(instant: fixture.clock.now())
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog    : [solo],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [solo.manifest.id: []],
                explicitBindings: []
            ),
            governor: ResourceGovernor(),
            adapter : adapter,
            clock   : clock
        )
        let launch = try await runtime.requestLaunch(owner: solo.manifest.id)
        let start  = try #require(adapter.lastStart(owner: solo.manifest.id))
        #expect(start.launchID == launch)
        await runtime.observeExit(start.incarnation, cause: .unexpected)
        let soloVersion = try AddonVersionIdentity(
            verifiedIdentity: solo.verifiedIdentity,
            version         : SemanticVersion(1, 0, 0)
        )
        #expect(await runtime.resourceHealthSnapshot(for: soloVersion)?.crashRetryCount == 0)
        #expect(await runtime.resourceHealthSnapshot(for: soloVersion)?.hasPendingRetry == false)
    }

    @Test
    func connectionLossRetainsOnlyClassifiedExitAuthorityAndWakeCancelsRetry() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.closeConnection(fixture.provider)
        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 1)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == true)
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .completed)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
        fixture.advance(1)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 1)
    }

    @Test
    func wakeWhileCrashDemandIsSuspendedCannotMintRetry() async throws {
        let fixture     = try await CrashServiceFixture()
        let gate        = CrashDemandGate()
        let runtime     = fixture.runtime
        let incarnation = fixture.provider.incarnation
        let exiting     = Task {
            await AddonRuntime.$crashDemandCheckpoint.withValue({
                await gate.pause()
            }) {
                await runtime.observeExit(incarnation, cause: .unexpected)
            }
        }

        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("Crash demand checkpoint did not finish within five seconds.")
                await gate.release()
            } catch is CancellationError {
                // Observed checkpoint released before timeout.
            } catch {
                Issue.record("Crash demand watchdog failed: \(error)")
                await gate.release()
            }
        }

        defer {
            watchdog.cancel()
            exiting.cancel()
            Task { await gate.release() }
        }

        #expect(await gate.waitForArrival())
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .deferred)
        await gate.release()
        await exiting.value
        let version = try fixture.version()
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 0)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
    }

    @Test
    func canonicalInterestExpiringDuringBrokerReadCannotDemandRetry() async throws {
        let fixture     = try await CrashServiceFixture()
        let gate        = CrashDemandGate()
        let runtime     = fixture.runtime
        let incarnation = fixture.provider.incarnation
        let exiting     = Task {
            await AddonRuntime.$crashDemandCheckpoint.withValue({
                await gate.pause()
            }) {
                await runtime.observeExit(incarnation, cause: .unexpected)
            }
        }

        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("Expiry checkpoint did not finish within five seconds.")
                await gate.release()
            } catch is CancellationError {
                // Observed checkpoint released before timeout.
            } catch {
                Issue.record("Expiry watchdog failed: \(error)")
                await gate.release()
            }
        }

        defer {
            watchdog.cancel()
            exiting.cancel()
            Task { await gate.release() }
        }

        #expect(await gate.waitForArrival())
        fixture.advance(3_600)
        await gate.release()
        await exiting.value
        let version = try fixture.version()
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 0)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
    }

    @Test
    func refusedProviderReservationKeepsTicketAndRefundsPoolUntilNextDuePass() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        let baseline = try #require(await fixture.runtime.diagnostics(owner: fixture.providerID)?.reservedStateBytes)
        let blocker  = try await fixture.governor.admit(.provider, owner: fixture.providerID)
        fixture.advance(1)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 1)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == true)
        #expect(await fixture.runtime.diagnostics(owner: fixture.providerID)?.reservedStateBytes == baseline)
        try await fixture.governor.release(blocker.id, owner: fixture.providerID)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 2)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
    }

    @Test
    func demandExpiringAfterDuePoolGrowthRefundsPreparedCapacity() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        let baseline = try #require(await fixture.runtime.diagnostics(owner: fixture.providerID)?.reservedStateBytes)
        fixture.advance(1)
        let gate         = CrashDemandGate(pauseOnCall: 2)
        let runtime      = fixture.runtime
        let deadlinePass = Task {
            try await AddonRuntime.$crashDemandCheckpoint.withValue({
                await gate.pause()
            }) {
                try await runtime.serviceDeadlines()
            }
        }

        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("The post-growth demand gate did not finish within five seconds.")
                await gate.release()
            } catch is CancellationError {
                // The exact due-launch lookup completed before timeout.
            } catch {
                Issue.record("The post-growth demand watchdog failed: \(error)")
                await gate.release()
            }
        }

        defer {
            watchdog.cancel()
            deadlinePass.cancel()
            Task { await gate.release() }
        }

        #expect(await gate.waitForArrival())
        fixture.advance(3_600)
        await gate.release()
        _ = try await deadlinePass.value
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 1)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
        #expect(await fixture.runtime.diagnostics(owner: fixture.providerID)?.reservedStateBytes == baseline)
        #expect(await fixture.governor.usage(.providers, owner: fixture.providerID) == 0)
    }

    @Test
    func stopDuringDueDemandPrecheckDrainsDeferredShutdown() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        fixture.advance(1)
        let gate         = CrashDemandGate()
        let runtime      = fixture.runtime
        let deadlinePass = Task {
            try await AddonRuntime.$crashDemandCheckpoint.withValue({
                await gate.pause()
            }) {
                try await runtime.serviceDeadlines()
            }
        }

        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("The due precheck gate did not finish within five seconds.")
                await gate.release()
            } catch is CancellationError {
                // The due precheck was released before timeout.
            } catch {
                Issue.record("The due precheck watchdog failed: \(error)")
                await gate.release()
            }
        }

        defer {
            watchdog.cancel()
            deadlinePass.cancel()
            Task { await gate.release() }
        }

        #expect(await gate.waitForArrival())
        let stopping = await fixture.runtime.requestStop()
        #expect(stopping.cleanupPending)
        await gate.release()
        _ = try await deadlinePass.value
        #expect(await fixture.runtime.requestStop().cleanupPending == false)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
        #expect(await fixture.governor.usage(.providers, owner: fixture.providerID) == 0)
    }

    @Test
    func lostDemandAtDueConsumesTicketWithoutLaunching() async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        fixture.advance(3_600)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
        #expect(fixture.adapter.startCount(owner: fixture.providerID) == 1)
    }

    @Test(arguments: [false, true])
    func disableOrStopAfterConnectionLossSuppressesLateClassifiedCrash(stop: Bool) async throws {
        let fixture = try await CrashServiceFixture()
        let version = try fixture.version()
        await fixture.runtime.closeConnection(fixture.provider)
        if stop {
            await fixture.runtime.stop()
        } else {
            await fixture.runtime.disable(owner: fixture.providerID)
        }

        await fixture.runtime.observeExit(fixture.provider.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.crashRetryCount == 0)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
    }

    @Test
    func rejectedDueStartHandoffSpendsTicketWithoutAutomaticReplay() async throws {
        let host = try await InvocationMessageHost.make(
            governor            : ResourceGovernor(),
            minor               : 4,
            maximumEnvelopeBytes: 524_288
        )
        do {
            let providerID = host.provider.identity.addonID
            let version    = try AddonVersionIdentity(
                verifiedIdentity: host.provider.identity,
                version         : SemanticVersion(1, 0, 0)
            )
            await host.runtime.observeExit(host.provider.incarnation, cause: .unexpected)
            #expect(await host.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == true)
            let before = host.adapter.starts.count
            host.adapter.rejectStartOwners = [providerID]
            host.clock.advance(1)
            _ = try await host.runtime.serviceDeadlines()
            #expect(host.adapter.starts.count == before)
            #expect(await host.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == false)
            #expect(await host.governor.usage(.providers, owner: providerID) == 0)
            host.adapter.rejectStartOwners = []
            _ = try await host.runtime.serviceDeadlines()
            #expect(host.adapter.starts.count == before)
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    @Test
    func delegatedModerateDuringRetryPreservesExactTicketUntilQuarantine() throws {
        let installed = try installedFixture("focus", publisher: "TEST-ONLY.health")
        let version   = try AddonVersionIdentity(
            verifiedIdentity: installed.verifiedIdentity,
            version         : SemanticVersion(1, 0, 0)
        )
        func instant(_ second: Int) -> RuntimeInstant {
            RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000 + Double(second)),
                monotonic: .seconds(second)
            )
        }

        var store = AddonHealthStore()
        _ = try store.register(version)
        let session = try store.bind(version, generation: ConnectionGeneration())
        guard case .retryAt(let ticket) = try store.crashed(
            session,
            demandExists: true,
            at          : instant(0)
        ) else {
            Issue.record("Demanded crash did not create a ticket.")
            return
        }

        #expect(try store.recordModerateDuringRetry(from: ticket, at: instant(1)) == .keep)
        #expect(try store.recordModerateDuringRetry(from: ticket, at: instant(2)) == .keep)
        #expect(store.pendingRetryTickets == [ticket])
        #expect(store.nextDeadline == .seconds(1))
        #expect(try store.recordModerateDuringRetry(from: ticket, at: instant(3)) == .quarantine)
        #expect(store.pendingRetryTickets.isEmpty)
        #expect(try store.recordModerateDuringRetry(from: ticket, at: instant(4)) == nil)
        #expect(store.snapshot(for: version)?.isQuarantined == true)
    }

    @Test
    func queuedActionDemandClosesAtItsExactCanonicalDeadline() throws {
        let fixture    = try ActionFixture()
        let now        = RuntimeInstant(wall: fixture.wall, monotonic: .zero)
        var dispatcher = ActionDispatcher()
        _ = try dispatcher.submit(
            fixture.request(),
            context: fixture.context(),
            at     : now
        )
        let job = try #require(dispatcher.peekReady(at: .zero))
        #expect(dispatcher.hasCurrentQueuedDemand(owner: fixture.owner, at: job.deadline - .nanoseconds(1)))
        #expect(!dispatcher.hasCurrentQueuedDemand(owner: fixture.owner, at: job.deadline))
    }
}
