//
//  ActionDispatcherTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct ActionDispatcherTests {
    @Test
    func duplicateRecoveryUsesOriginalRequestAndBindingWithoutReplaying() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        var dispatcher = ActionDispatcher()
        #expect(try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : now
        ) == .admitted)
        #expect(try dispatcher.submit(
            request,
            context: fixture.context(revision: 2),
            at     : now
        ) == .duplicate(.queued))
        for context in try [
            fixture.context(digest: "changed"),
            fixture.context(publisher: "different"),
            fixture.context(feature: "other"),
            fixture.context(eligibility: .unavailable)
        ] {
            #expect(throws: (any Error).self) {
                try dispatcher.submit(
                    request,
                    context: context,
                    at     : now
                )
            }
        }
        #expect(throws: (any Error).self) {
            try dispatcher.submit(
                fixture.request(
                    id   : request.requestID,
                    input: Data([9])
                ),
                context: fixture.context(),
                at     : now
            )
        }
        #expect(dispatcher.historyCount == 1)
        #expect(dispatcher.jobCount == 1)
    }

    @Test
    func queueAndSharedBudgetRejectionRollBackNewHistory() throws {
        let fixture = try ActionFixture()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        var dispatcher = ActionDispatcher()
        for _ in 0..<4 {
            _ = try dispatcher.submit(
                fixture.request(),
                context: fixture.context(),
                at     : now
            )
        }
        let bytes = dispatcher.retainedBytes
        let rejected = try fixture.request()
        #expect(throws: (any Error).self) {
            try dispatcher.submit(
                rejected,
                context: fixture.context(),
                at     : now
            )
        }
        #expect(dispatcher.historyCount == 4)
        #expect(dispatcher.bindingCount == 4)
        #expect(dispatcher.retainedBytes == bytes)
        var tiny = ActionDispatcher(maximumRetainedBytes: 80_000)
        #expect(throws: (any Error).self) {
            try tiny.submit(
                rejected,
                context: fixture.context(),
                at     : now
            )
        }
        #expect(tiny.historyCount == 0)
        #expect(tiny.jobCount == 0)
        #expect(tiny.retainedBytes == 0)
    }

    @Test
    func secondIntentRevalidatesRevisionAndTicketsAreOneUse() throws {
        let fixture = try ActionFixture()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        var dispatcher = ActionDispatcher()
        let first = try fixture.request()
        let second = try fixture.request()
        _ = try dispatcher.submit(
            first,
            context: fixture.context(),
            at     : now
        )
        _ = try dispatcher.submit(
            second,
            context: fixture.context(),
            at     : now
        )
        let ticketValue = dispatcher.takeReady(at: .zero)
        let ticket = try #require(ticketValue)
        let generation = ConnectionGeneration()
        let deliveryValue = try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: generation,
            at        : now
        )
        let delivery = try #require(deliveryValue)
        #expect(try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: generation,
            at        : now
        ) == nil)
        #expect(dispatcher.takeReady(at: .zero) == nil)
        #expect(try dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            outcome   : .completed(payload: Data([1])),
            at        : .seconds(1)
        ))
        let queuedValue = dispatcher.takeReady(at: .seconds(1))
        let queued = try #require(queuedValue)
        #expect(throws: ActionAuthorizer.Failure.staleRevision) {
            try dispatcher.consume(
                queued,
                context   : fixture.context(revision: 2),
                generation: generation,
                at        : RuntimeInstant(
                    wall      : fixture.wall,
                    monotonic : .seconds(1)
                )
            )
        }
        let state = try dispatcher.submit(
            second,
            context: fixture.context(revision: 2),
            at     : now
        )
        guard case .duplicate(.finished(.rejected)) = state else { Issue.record("Stale intent needs rejection"); return }
        #expect(dispatcher.runningCount == 0)
        #expect(dispatcher.jobCount == 0)
    }

    @Test
    func disableRevokesReservedTicketsAndKeepsSentSlotsUntilActualExit() throws {
        let fixture = try ActionFixture()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        var dispatcher = ActionDispatcher()
        _ = try dispatcher.submit(
            fixture.request(),
            context: fixture.context(),
            at     : now
        )
        let ticketValue = dispatcher.takeReady(at: .zero)
        let ticket = try #require(ticketValue)
        #expect(dispatcher.disable(owner: fixture.owner).isEmpty)
        #expect(try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: ConnectionGeneration(),
            at        : now
        ) == nil)
        #expect(dispatcher.runningCount == 0)
        let request = try fixture.request()
        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : now
        )
        let nextValue = dispatcher.takeReady(at: .zero)
        let next = try #require(nextValue)
        let generation = ConnectionGeneration()
        let deliveryValue = try dispatcher.consume(
            next,
            context   : fixture.context(),
            generation: generation,
            at        : now
        )
        let delivery = try #require(deliveryValue)
        _ = try dispatcher.submit(
            fixture.request(),
            context: fixture.context(),
            at     : now
        )
        #expect(dispatcher.disable(owner: fixture.owner) == [delivery])
        #expect(dispatcher.runningCount == 1)
        #expect(try !dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            outcome   : .completed(payload: Data()),
            at        : .seconds(1)
        ))
        #expect(try !dispatcher.observeExit(
            delivery,
            owner     : fixture.owner,
            generation: ConnectionGeneration()
        ))
        #expect(dispatcher.runningCount == 1)
        #expect(try dispatcher.observeExit(
            delivery,
            owner     : fixture.owner,
            generation: generation
        ))
        #expect(try !dispatcher.observeExit(
            delivery,
            owner     : fixture.owner,
            generation: generation
        ))
        #expect(dispatcher.runningCount == 0)
        #expect(try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : now
        ) == .duplicate(.finished(.outcomeUnknown)))
    }

    @Test
    func timeoutUsesMonotonicDeadlineAndHistoryExpiresWithoutFreeingRealWork() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        var dispatcher = ActionDispatcher()
        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .seconds(100)
            )
        )
        #expect(dispatcher.nextDeadline == .seconds(120))
        let ticketValue = dispatcher.takeReady(at: .seconds(101))
        let ticket = try #require(ticketValue)
        let generation = ConnectionGeneration()
        let deliveryValue = try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: generation,
            at        : RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(-3_600),
                monotonic: .seconds(101)
            )
        )
        let delivery = try #require(deliveryValue)
        #expect(dispatcher.expire(at: .seconds(120)) == [delivery])
        #expect(dispatcher.nextDeadline == .seconds(700))
        #expect(dispatcher.runningCount == 1)
        #expect(try !dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            outcome   : .completed(payload: Data()),
            at        : .seconds(121)
        ))
        _ = dispatcher.expire(at: .seconds(700))
        #expect(dispatcher.historyCount == 0)
        #expect(dispatcher.bindingCount == 1)
        #expect(dispatcher.hasRecord(publicationID: request.publicationID))
        #expect(throws: (any Error).self) {
            try dispatcher.submit(
                request,
                context: fixture.context(),
                at     : RuntimeInstant(
                    wall     : fixture.wall,
                    monotonic: .seconds(700)
                )
            )
        }
        #expect(try dispatcher.observeExit(
            delivery,
            owner     : fixture.owner,
            generation: generation
        ))
        #expect(dispatcher.bindingCount == 0)
        #expect(dispatcher.retainedBytes == 0)
        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .seconds(701)
            )
        )
        #expect(try !dispatcher.observeExit(
            delivery,
            owner     : fixture.owner,
            generation: generation
        ))
        #expect(dispatcher.jobCount == 1)
    }

    @Test
    func globalConcurrencyIsTwoAndStopCannotReleaseSentJobs() throws {
        var dispatcher = ActionDispatcher()
        for name in ["com.example.one", "com.example.two", "com.example.three"] {
            let fixture = try ActionFixture(ownerName: name)
            _ = try dispatcher.submit(
                fixture.request(),
                context: fixture.context(),
                at     : RuntimeInstant(
                    wall     : fixture.wall,
                    monotonic: .zero
                )
            )
        }
        #expect(dispatcher.takeReady(at: .zero) != nil)
        #expect(dispatcher.takeReady(at: .zero) != nil)
        #expect(dispatcher.takeReady(at: .zero) == nil)
        _ = dispatcher.stop()
        #expect(dispatcher.runningCount == 0)
        #expect(dispatcher.jobCount == 0)
        let fixture = try ActionFixture()
        #expect(throws: (any Error).self) {
            try dispatcher.submit(
                fixture.request(),
                context: fixture.context(),
                at     : RuntimeInstant(
                    wall     : fixture.wall,
                    monotonic: .zero
                )
            )
        }
        _ = dispatcher.expire(at: .seconds(600))
        #expect(dispatcher.bindingCount == 0)
        #expect(dispatcher.retainedBytes == 0)
    }
    @Test
    func disconnectAfterAcknowledgementKeepsUnknownOutcomeAndSlotUntilExit() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        let generation = ConnectionGeneration()
        var dispatcher = ActionDispatcher()
        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : now
        )
        let ticketValue = dispatcher.takeReady(at: .zero)
        let ticket = try #require(ticketValue)
        let deliveryValue = try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: generation,
            at        : now
        )
        let delivery = try #require(deliveryValue)
        #expect(dispatcher.acknowledge(
            delivery,
            owner     : fixture.owner,
            generation: ConnectionGeneration(),
            at        : .seconds(1)
        ) == false)
        #expect(dispatcher.acknowledge(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            at        : .seconds(1)
        ) == true)
        #expect(try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : now
        ) == .duplicate(.acknowledged(generation)))
        #expect(dispatcher.connectionLost(
            owner     : fixture.owner,
            generation: ConnectionGeneration()
        ).isEmpty)
        #expect(dispatcher.connectionLost(
            owner     : fixture.owner,
            generation: generation
        ) == [delivery])
        #expect(dispatcher.connectionLost(
            owner     : fixture.owner,
            generation: generation
        ).isEmpty)
        #expect(dispatcher.runningCount == 1)
        #expect(try dispatcher.submit(
            request,
            context: fixture.context(revision: 2),
            at     : now
        ) == .duplicate(.finished(.outcomeUnknown)))
        #expect(dispatcher.acknowledge(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            at        : .seconds(2)
        ) == false)
        #expect(try dispatcher.observeExit(
            delivery,
            owner     : fixture.owner,
            generation: generation
        ))
        #expect(dispatcher.runningCount == 0)
    }

    @Test
    func finalDeliveryChecksCurrentPermissionAndUnsentDeadline() throws {
        let fixture = try ActionFixture()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        for expired in [false, true] {
            let request = try fixture.request()
            var dispatcher = ActionDispatcher()
            _ = try dispatcher.submit(
                request,
                context: fixture.context(),
                at     : now
            )
            let value = dispatcher.takeReady(at: .zero)
            let ticket = try #require(value)
            let context = try fixture.context(eligibility: expired ? .available : .privacyRedacted)
            #expect(throws: (any Error).self) {
                try dispatcher.consume(
                    ticket,
                    context   : context,
                    generation: ConnectionGeneration(),
                    at        : RuntimeInstant(
                        wall     : fixture.wall,
                        monotonic: expired ? .seconds(20) : .seconds(1)
                    )
                )
            }
            guard case .duplicate(.finished(.rejected)) = try dispatcher.submit(
                request,
                context: fixture.context(),
                at     : now
            )
            else { Issue.record("Unsent work must be rejected"); continue }
            #expect(dispatcher.runningCount == 0)
            #expect(dispatcher.jobCount == 0)
            _ = dispatcher.expire(at: .seconds(600))
            #expect(dispatcher.retainedBytes == 0)
        }
    }

    @Test
    func completedOutcomeRetainsBindingAndMaximumResultWithinSharedBudget() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        let generation = ConnectionGeneration()
        var dispatcher = ActionDispatcher(maximumRetainedBytes: 100_000)
        _ = try dispatcher.submit(
            request,
            context: fixture.context(),
            at     : now
        )
        let value = dispatcher.takeReady(at: .zero)
        let ticket = try #require(value)
        let sent = try dispatcher.consume(
            ticket,
            context   : fixture.context(),
            generation: generation,
            at        : now
        )
        let delivery = try #require(sent)
        let foreign = try ActionFixture(ownerName: "com.example.foreign")
        #expect(try !dispatcher.complete(
            delivery,
            owner     : foreign.owner,
            generation: generation,
            outcome   : .completed(payload: Data()),
            at        : .seconds(1)
        ))
        #expect(try !dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: ConnectionGeneration(),
            outcome   : .completed(payload: Data()),
            at        : .seconds(1)
        ))
        #expect(throws: AddonFailure.self) {
            try dispatcher.complete(
                delivery,
                owner     : fixture.owner,
                generation: generation,
                outcome   : .completed(payload: Data(count: 65_537)),
                at        : .seconds(1)
            )
        }
        #expect(try dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            outcome   : .completed(payload: Data(count: 65_536)),
            at        : .seconds(1)
        ))
        #expect(dispatcher.retainedBytes <= 100_000)
        #expect(dispatcher.bindingCount == 1)
        #expect(try !dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            outcome   : .completed(payload: Data()),
            at        : .seconds(2)
        ))
        #expect(throws: (any Error).self) {
            try dispatcher.submit(
                request,
                context: fixture.context(digest: "changed"),
                at     : now
            )
        }
        _ = dispatcher.expire(at: .seconds(599))
        #expect(dispatcher.bindingCount == 1)
        _ = dispatcher.expire(at: .seconds(600))
        #expect(dispatcher.bindingCount == 0)
        #expect(dispatcher.retainedBytes == 0)
    }

    @Test
    func completedResultRecoverySurvivesPublicationRemovalWithoutRenewingHistory() throws {
        let fixture = try ActionFixture()
        let request = try fixture.request()
        let live = try fixture.context()
        let now = RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        )
        let generation = ConnectionGeneration()

        func withoutPublication(_ context: ActionAuthorizer.Context) -> ActionAuthorizer.Context {
            ActionAuthorizer.Context(
                installed  : context.installed,
                resolution : context.resolution,
                featureID  : context.featureID,
                publication: nil,
                eligibility: context.eligibility
            )
        }

        var dispatcher = ActionDispatcher()
        _ = try dispatcher.submit(
            request,
            context: live,
            at     : now
        )
        let ticketValue = dispatcher.takeReady(at: .zero)
        let ticket = try #require(ticketValue)
        let deliveryValue = try dispatcher.consume(
            ticket,
            context   : live,
            generation: generation,
            at        : now
        )
        let delivery = try #require(deliveryValue)
        #expect(try dispatcher.complete(
            delivery,
            owner     : fixture.owner,
            generation: generation,
            outcome   : .completed(payload: Data([42])),
            at        : .seconds(1)
        ))
        let retainedBytes = dispatcher.retainedBytes
        #expect(dispatcher.nextDeadline == .seconds(600))

        let recovery = withoutPublication(live)
        #expect(try dispatcher.submit(
            request,
            context: recovery,
            at     : RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(300),
                monotonic: .seconds(300)
            )
        ) == .duplicate(.finished(.completed(payload: Data([42])))))
        #expect(dispatcher.historyCount == 1)
        #expect(dispatcher.bindingCount == 1)
        #expect(dispatcher.jobCount == 0)
        #expect(dispatcher.retainedBytes == retainedBytes)
        #expect(dispatcher.nextDeadline == .seconds(600))

        for context in try [
            fixture.context(enabled: false),
            fixture.context(blockedRoot: true),
            fixture.context(blockedFeature: "controls"),
            fixture.context(eligibility: .unavailable),
            fixture.context(eligibility: .hidden),
            fixture.context(eligibility: .privacyRedacted),
            fixture.context(digest: "changed"),
            fixture.context(publisher: "different"),
            fixture.context(feature: "other")
        ] {
            #expect(throws: (any Error).self) {
                try dispatcher.submit(
                    request,
                    context: withoutPublication(context),
                    at     : now
                )
            }
        }
        #expect(throws: AddonFailure.self) {
            try dispatcher.submit(
                fixture.request(
                    id   : request.requestID,
                    input: Data([9])
                ),
                context: recovery,
                at     : now
            )
        }
        #expect(dispatcher.retainedBytes == retainedBytes)
        #expect(try dispatcher.submit(
            request,
            context: recovery,
            at     : RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(599),
                monotonic: .seconds(599)
            )
        ) == .duplicate(.finished(.completed(payload: Data([42])))))
        _ = dispatcher.expire(at: .seconds(600))
        #expect(dispatcher.historyCount == 0)
        #expect(dispatcher.bindingCount == 0)
        #expect(dispatcher.retainedBytes == 0)
        #expect(dispatcher.nextDeadline == nil)
        #expect(throws: ActionAuthorizer.Failure.identityMismatch) {
            try dispatcher.submit(
                request,
                context: recovery,
                at     : now
            )
        }
        #expect(dispatcher.jobCount == 0)

        // No stored result exists in this coordinator: nil publication cannot
        // admit a new effect, nor authorize final delivery of an earlier intent.
        var fresh = ActionDispatcher()
        #expect(throws: ActionAuthorizer.Failure.identityMismatch) {
            try fresh.submit(
                request,
                context: recovery,
                at     : now
            )
        }
        #expect(fresh.historyCount == 0)
        #expect(fresh.retainedBytes == 0)
        _ = try fresh.submit(
            request,
            context: live,
            at     : now
        )
        let reservedValue = fresh.takeReady(at: .zero)
        let reserved = try #require(reservedValue)
        #expect(throws: ActionAuthorizer.Failure.identityMismatch) {
            try fresh.consume(
                reserved,
                context   : recovery,
                generation: generation,
                at        : now
            )
        }
        #expect(fresh.jobCount == 0)
        #expect(fresh.runningCount == 0)
    }

}
