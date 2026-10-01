//
//  TransportServiceClientTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

@Suite(.serialized, .timeLimit(.minutes(1)))
struct TransportServiceClientTests {

    @Test
    func capacityCountsQuarantineAndReusesOnlyAcknowledgedRemoval() async throws {
        let channel   = SubscriptionSDKChannel()
        let delivered = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let client    = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { delivered.continuation.yield($0.response.payload) }
        )
        let grants  = try (0..<64).map { _ in try channel.grant() }
        let aliases = (0..<64).map { _ in UUID() }

        for index in 0..<64 {
            channel.result = .subscribed(aliases[index])
            #expect(try await client.subscribe(
                requirementID: "requirement.\(index)",
                grant        : grants[index]
            ) == aliases[index])
        }
        #expect(channel.sequences == Array(1...64).map(UInt64.init))

        let extraGrant = try channel.grant(), extraAlias = UUID()
        channel.result = .subscribed(extraAlias)
        await subscriptionExpect(.resourceDenied) {
            _ = try await client.subscribe(requirementID: "extra", grant: extraGrant)
        }
        #expect(channel.sequences.count == 64) // Overflow is rejected before the wire boundary.

        channel.result = .subscribed(aliases[0])
        #expect(try await client.subscribe(requirementID: "requirement.0", grant: grants[0]) == aliases[0])

        channel.result = .outcomeUnknown
        await subscriptionExpect(.outcomeUnknown) { try await client.unsubscribe(subscriptionID: aliases[0]) }

        channel.result = .subscribed(extraAlias)
        await subscriptionExpect(.resourceDenied) {
            _ = try await client.subscribe(requirementID: "extra", grant: extraGrant)
        }
        #expect(channel.sequences.count == 66) // An uncertain removal retains its bounded slot.
        #expect(try await client.invoke(channel.invocation(), grant: grants[1]).payload == Data([9]))

        channel.result = .acknowledged
        try await client.unsubscribe(subscriptionID: aliases[1])

        channel.result = .subscribed(extraAlias)
        #expect(try await client.subscribe(requirementID: "extra", grant: extraGrant) == extraAlias)
        await subscriptionExpect(.resourceDenied) {
            _ = try await client.subscribe(requirementID: "overflow.again", grant: extraGrant)
        }
        #expect(channel.sequences == Array(1...69).map(UInt64.init))

        for index in 0..<2 {
            let stale = try ServiceEvent(
                subscriptionID: aliases[index],
                token         : grants[index],
                response      : channel.response()
            )
            await subscriptionExpect(.permissionDenied) { try await channel.emit(stale) }
        }

        try await channel.emit(ServiceEvent(
            subscriptionID: extraAlias,
            token         : extraGrant,
            response      : channel.response()
        ))
        #expect(await subscriptionNextPayload(delivered.stream) == Data([9]))

        delivered.continuation.finish()
        await client.close()
        #expect(channel.closeCount == 1)
    }

    @Test(arguments: [false, true])
    func repeatedSubscribePreservesOnlyLatestForConfirmedFullGrant(changedGrant: Bool) async throws {
        let channel      = SubscriptionSDKChannel()
        let firstHandler = SubscriptionSDKGate(), exchangeGate = SubscriptionSDKGate()
        let delivered    = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let client       = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { event in
                if event.response.payload == Data([0]) {
                    await firstHandler.pause()
                } else {
                    delivered.continuation.yield(event.response.payload)
                }
            }
        )
        let original = try channel.grant()
        let grant    = changedGrant ? try Grant(
            id        : original.id,
            owner     : original.owner,
            serviceID : original.serviceID,
            scope     : original.scope,
            expiresAt : original.expiresAt.addingTimeInterval(1),
            generation: original.generation,
            cost      : original.cost
        ) : original
        let alias = try await client.subscribe(requirementID: "requirement", grant: original)

        func event(
            _ value: UInt8,
            token  : Grant
        ) throws -> ServiceEvent {
            try ServiceEvent(
                subscriptionID: alias,
                token         : token,
                response      : ServiceResponse(
                    schemaVersion: 1,
                    contractID   : "service",
                    operation    : "read",
                    payload      : Data([value])
                )
            )
        }

        try await channel.emit(event(0, token: original))
        await firstHandler.waitForArrival()
        try await channel.emit(event(1, token: original))

        channel.gate = exchangeGate
        let repeated = Task { try await client.subscribe(requirementID: "requirement", grant: grant) }
        await exchangeGate.waitForArrival()
        try await channel.emit(event(2, token: grant)) // Physical receipt already consumed, before terminal bytes.
        await exchangeGate.release()
        #expect(try await repeated.value == alias)

        if changedGrant {
            await subscriptionExpect(.permissionDenied) { try await channel.emit(event(3, token: original)) }
        }

        await firstHandler.release()
        // Gates establish ordering; this timer is only a finite missing-callback watchdog.
        let latest = await subscriptionNextPayload(delivered.stream)
        #expect(latest == Data([2]))

        delivered.continuation.finish()
        await client.close()
    }

    @Test(arguments: [false, true])
    func noEffectUnsubscribePreservesLatestAlreadyReceiptedEvent(notSent: Bool) async throws {
        let channel      = SubscriptionSDKChannel()
        let firstHandler = SubscriptionSDKGate(), delivered = SubscriptionSDKGate(), exchangeGate = SubscriptionSDKGate()
        let observed     = SubscriptionSDKObservation()
        let client       = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { event in
                if event.response.payload == Data([0]) {
                    await firstHandler.pause()
                } else {
                    await observed.record(event.response.payload)
                    await delivered.arrive()
                }
            }
        )
        let grant = try channel.grant()
        let alias = try await client.subscribe(requirementID: "requirement", grant: grant)

        func event(_ byte: UInt8) throws -> ServiceEvent {
            try ServiceEvent(
                subscriptionID: alias,
                token         : grant,
                response      : ServiceResponse(
                    schemaVersion: 1,
                    contractID   : "service",
                    operation    : "read",
                    payload      : Data([byte])
                )
            )
        }

        try await channel.emit(event(0))
        await firstHandler.waitForArrival()
        try await channel.emit(event(1)) // Paid queued latest while the first handler is running.

        channel.gate                = exchangeGate
        channel.result              = .refused(code: .permissionDenied, reason: "No effects")
        channel.rejectBeforeHandoff = notSent
        let unsubscribing = Task { try await client.unsubscribe(subscriptionID: alias) }
        await exchangeGate.waitForArrival()

        var retained = true
        do {
            try await channel.emit(event(2))
        } catch {
            retained = false
            Issue.record("Current receipted event rejected during unresolved unsubscribe: \(error)")
        }
        #expect(await observed.payload == nil)

        await exchangeGate.release()
        do {
            try await unsubscribing.value
            Issue.record("Expected no-effect refusal")
        } catch {
            #expect((error as? AddonFailure)?.code == (notSent ? .dependencyUnavailable : .permissionDenied))
        }

        await firstHandler.release()
        if retained {
            await delivered.waitForArrival()
            #expect(await observed.payload == Data([2])) // No new host event triggers this callback.
        }

        await client.close()
    }

    @Test
    func wholeClientUsesOneSequenceAndKnownRefusalsPermitReuse() async throws {
        let channel = SubscriptionSDKChannel()
        let client  = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { _ in }
        )
        let grant = try channel.grant()
        let alias = try await client.subscribe(requirementID: "requirement", grant: grant)
        #expect(try await client.invoke(channel.invocation(), grant: grant).payload == Data([9]))

        channel.result = .refused(code: .permissionDenied, reason: "Denied")
        await subscriptionExpect(.permissionDenied) {
            _ = try await client.subscribe(requirementID: "requirement", grant: grant)
        }

        channel.result = nil
        try await client.unsubscribe(subscriptionID: alias)
        #expect(channel.sequences == [1, 2, 3, 4])

        await client.close()
        await client.close()
        #expect(channel.closeCount == 1)
    }

    @Test(arguments: [false, true])
    func malformedControlAndDescriptorDriftPoisonBothFamilies(drift: Bool) async throws {
        let channel = SubscriptionSDKChannel()
        let client  = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { _ in }
        )
        let grant = try channel.grant()
        channel.damage             = !drift
        channel.driftAfterExchange = drift

        await subscriptionExpect(.outcomeUnknown) {
            _ = try await client.subscribe(requirementID: "requirement", grant: grant)
        }
        #expect(channel.closeCount == 1)
        await #expect(throws: AddonFailure.self) { _ = try await client.invoke(channel.invocation(), grant: grant) }

        await client.close()
    }

    @Test
    func unknownUnsubscribeQuarantinesAliasEvenIfLaterSubscribeReturnsIt() async throws {
        let channel = SubscriptionSDKChannel()
        let client  = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { _ in }
        )
        let grant = try channel.grant()
        let id    = try await client.subscribe(requirementID: "requirement", grant: grant)

        channel.result = .outcomeUnknown
        await subscriptionExpect(.outcomeUnknown) { try await client.unsubscribe(subscriptionID: id) }

        channel.result = nil
        // A correlated wire unknown settles its operation; only the alias is
        // quarantined. It must not poison a later independent invocation.
        #expect(try await client.invoke(channel.invocation(), grant: grant).payload == Data([9]))
        await subscriptionExpect(.outcomeUnknown) {
            _ = try await client.subscribe(requirementID: "requirement", grant: grant)
        }
        #expect(channel.sequences == [1, 2, 3, 4])

        await client.close()
    }

    @Test
    func preCancelledControlDoesNotSendAndSequenceNeverWraps() async throws {
        let channel  = SubscriptionSDKChannel()
        let exchange = try ServiceConnectionExchange(channel: channel, lastSequence: UInt64.max - 1)
        let request  = try ServiceControlRequest(
            requestID: UUID(),
            action   : .subscribe(requirementID: "requirement", grantID: UUID())
        )
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }

            return try await exchange.control(request)
        }

        do {
            _ = try await cancelled.value
            Issue.record("Cancelled operation sent")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(channel.sequences.isEmpty)

        _ = try await exchange.control(request)
        await subscriptionExpect(.sessionRevoked) {
            _ = try await exchange.invoke(grantID: UUID(), invocation: channel.invocation())
        }
        #expect(channel.sequences == [UInt64.max])

        await exchange.close()
    }

    @Test(arguments: [false, true])
    func exposedCancelAndCloseJoinOnePhysicalDrain(control: Bool) async throws {
        let channel  = SubscriptionSDKChannel()
        let exchange = try ServiceConnectionExchange(channel: channel)
        let gate     = SubscriptionSDKGate()
        channel.gate = gate

        let work = Task {
            if control {
                _ = try await exchange.control(ServiceControlRequest(
                    requestID: UUID(),
                    action   : .unsubscribe(subscriptionID: UUID())
                ))
            } else {
                _ = try await exchange.invoke(grantID: UUID(), invocation: channel.invocation())
            }
        }

        await gate.waitForArrival()
        work.cancel()
        let close = Task { await exchange.close() }
        await channel.closing.waitForArrival()
        await subscriptionExpect(.sessionRevoked) {
            _ = try await exchange.control(ServiceControlRequest(
                requestID: UUID(),
                action   : .unsubscribe(subscriptionID: UUID())
            ))
        }
        #expect(channel.closeCount == 1)

        await gate.release()
        do {
            try await work.value
            Issue.record("Exposed cancellation returned success")
        } catch {
            #expect((error as? AddonFailure)?.code == .outcomeUnknown)
        }

        await close.value
        #expect(channel.closeCount == 1)
    }

    @Test
    func earlyEventRequiresConfirmedAliasAndExactGrantSnapshot() async throws {
        let channel  = SubscriptionSDKChannel()
        let observed = SubscriptionSDKGate()
        let client   = try TransportServiceClient(
            channel    : channel,
            owner      : channel.owner,
            handleEvent: { _ in await observed.arrive() }
        )
        let grant = try channel.grant()
        channel.earlyEvent = try ServiceEvent(
            subscriptionID: channel.alias,
            token         : grant,
            response      : channel.response()
        )
        _ = try await client.subscribe(requirementID: "requirement", grant: grant)
        await observed.waitForArrival()

        let foreign = try ServiceEvent(
            subscriptionID: UUID(),
            token         : grant,
            response      : channel.response()
        )
        await subscriptionExpect(.permissionDenied) { try await channel.emit(foreign) }

        let changed = try Grant(
            id        : grant.id,
            owner     : grant.owner,
            serviceID : grant.serviceID,
            scope     : grant.scope,
            expiresAt : grant.expiresAt.addingTimeInterval(1),
            generation: grant.generation,
            cost      : grant.cost
        )
        let altered = try ServiceEvent(
            subscriptionID: channel.alias,
            token         : changed,
            response      : channel.response()
        )
        await subscriptionExpect(.permissionDenied) { try await channel.emit(altered) }

        let stale = try Grant(
            id        : grant.id,
            owner     : grant.owner,
            serviceID : grant.serviceID,
            scope     : grant.scope,
            expiresAt : grant.expiresAt,
            generation: ConnectionGeneration(),
            cost      : grant.cost
        )
        let staleEvent = try ServiceEvent(
            subscriptionID: channel.alias,
            token         : stale,
            response      : channel.response()
        )
        await subscriptionExpect(.permissionDenied) { try await channel.emit(staleEvent) }

        await client.close()
        let late = try ServiceEvent(
            subscriptionID: channel.alias,
            token         : grant,
            response      : channel.response()
        )
        await subscriptionExpect(.sessionRevoked) { try await channel.emit(late) }
    }
}

private func subscriptionExpect(
    _ code: AddonFailure.Code,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("Expected \(code)")
    } catch {
        #expect((error as? AddonFailure)?.code == code)
    }
}

private func subscriptionNextPayload(_ stream: AsyncStream<Data>) async -> Data? {
    await withTaskGroup(of: Data?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()

            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))

            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()

        return result
    }
}
