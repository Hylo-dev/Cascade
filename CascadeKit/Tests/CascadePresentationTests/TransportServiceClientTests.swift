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
    @Test func capacityCountsQuarantineAndReusesOnlyAcknowledgedRemoval() async throws {
        let channel = SubscriptionSDKChannel()
        let delivered = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let client = try TransportServiceClient(channel: channel, owner: channel.owner,
            handleEvent: { delivered.continuation.yield($0.response.payload) })
        let grants = try (0..<64).map { _ in try channel.grant() }
        let aliases = (0..<64).map { _ in UUID() }
        for index in 0..<64 {
            channel.result = .subscribed(aliases[index])
            #expect(try await client.subscribe(requirementID: "requirement.\(index)", grant: grants[index]) == aliases[index])
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
            let stale = try ServiceEvent(subscriptionID: aliases[index], token: grants[index], response: channel.response())
            await subscriptionExpect(.permissionDenied) { try await channel.emit(stale) }
        }
        try await channel.emit(ServiceEvent(subscriptionID: extraAlias, token: extraGrant, response: channel.response()))
        #expect(await subscriptionNextPayload(delivered.stream) == Data([9]))
        delivered.continuation.finish()
        await client.close()
        #expect(channel.closeCount == 1)
    }

    @Test(arguments: [false, true])
    func repeatedSubscribePreservesOnlyLatestForConfirmedFullGrant(changedGrant: Bool) async throws {
        let channel = SubscriptionSDKChannel()
        let firstHandler = SubscriptionSDKGate(), exchangeGate = SubscriptionSDKGate()
        let delivered = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let client = try TransportServiceClient(channel: channel, owner: channel.owner, handleEvent: { event in
            if event.response.payload == Data([0]) { await firstHandler.pause() }
            else { delivered.continuation.yield(event.response.payload) }
        })
        let original = try channel.grant()
        let grant = changedGrant ? try Grant(id: original.id, owner: original.owner,
            serviceID: original.serviceID, scope: original.scope,
            expiresAt: original.expiresAt.addingTimeInterval(1), generation: original.generation,
            cost: original.cost) : original
        let alias = try await client.subscribe(requirementID: "requirement", grant: original)
        func event(_ value: UInt8, token: Grant) throws -> ServiceEvent {
            try ServiceEvent(subscriptionID: alias, token: token, response: ServiceResponse(schemaVersion: 1,
                contractID: "service", operation: "read", payload: Data([value])))
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
        let channel = SubscriptionSDKChannel()
        let firstHandler = SubscriptionSDKGate(), delivered = SubscriptionSDKGate(), exchangeGate = SubscriptionSDKGate()
        let observed = SubscriptionSDKObservation()
        let client = try TransportServiceClient(channel: channel, owner: channel.owner, handleEvent: { event in
            if event.response.payload == Data([0]) { await firstHandler.pause() }
            else { await observed.record(event.response.payload); await delivered.arrive() }
        })
        let grant = try channel.grant()
        let alias = try await client.subscribe(requirementID: "requirement", grant: grant)
        func event(_ byte: UInt8) throws -> ServiceEvent {
            try ServiceEvent(subscriptionID: alias, token: grant, response: ServiceResponse(schemaVersion: 1,
                contractID: "service", operation: "read", payload: Data([byte])))
        }
        try await channel.emit(event(0))
        await firstHandler.waitForArrival()
        try await channel.emit(event(1)) // Paid queued latest while the first handler is running.
        channel.gate = exchangeGate
        channel.result = .refused(code: .permissionDenied, reason: "No effects")
        channel.rejectBeforeHandoff = notSent
        let unsubscribing = Task { try await client.unsubscribe(subscriptionID: alias) }
        await exchangeGate.waitForArrival()
        var retained = true
        do { try await channel.emit(event(2)) }
        catch { retained = false; Issue.record("Current receipted event rejected during unresolved unsubscribe: \(error)") }
        #expect(await observed.payload == nil)
        await exchangeGate.release()
        do { try await unsubscribing.value; Issue.record("Expected no-effect refusal") }
        catch { #expect((error as? AddonFailure)?.code == (notSent ? .dependencyUnavailable : .permissionDenied)) }
        await firstHandler.release()
        if retained {
            await delivered.waitForArrival()
            #expect(await observed.payload == Data([2])) // No new host event triggers this callback.
        }
        await client.close()
    }

    @Test func wholeClientUsesOneSequenceAndKnownRefusalsPermitReuse() async throws {
        let channel = SubscriptionSDKChannel()
        let client = try TransportServiceClient(channel: channel, owner: channel.owner, handleEvent: { _ in })
        let grant = try channel.grant()
        let alias = try await client.subscribe(requirementID: "requirement", grant: grant)
        #expect(try await client.invoke(channel.invocation(), grant: grant).payload == Data([9]))
        channel.result = .refused(code: .permissionDenied, reason: "Denied")
        await subscriptionExpect(.permissionDenied) { _ = try await client.subscribe(requirementID: "requirement", grant: grant) }
        channel.result = nil
        try await client.unsubscribe(subscriptionID: alias)
        #expect(channel.sequences == [1, 2, 3, 4])
        await client.close(); await client.close()
        #expect(channel.closeCount == 1)
    }

    @Test(arguments: [false, true])
    func malformedControlAndDescriptorDriftPoisonBothFamilies(drift: Bool) async throws {
        let channel = SubscriptionSDKChannel()
        let client = try TransportServiceClient(channel: channel, owner: channel.owner, handleEvent: { _ in })
        let grant = try channel.grant()
        channel.damage = !drift; channel.driftAfterExchange = drift
        await subscriptionExpect(.outcomeUnknown) { _ = try await client.subscribe(requirementID: "requirement", grant: grant) }
        #expect(channel.closeCount == 1)
        await #expect(throws: AddonFailure.self) { _ = try await client.invoke(channel.invocation(), grant: grant) }
        await client.close()
    }

    @Test func unknownUnsubscribeQuarantinesAliasEvenIfLaterSubscribeReturnsIt() async throws {
        let channel = SubscriptionSDKChannel()
        let client = try TransportServiceClient(channel: channel, owner: channel.owner, handleEvent: { _ in })
        let grant = try channel.grant()
        let id = try await client.subscribe(requirementID: "requirement", grant: grant)
        channel.result = .outcomeUnknown
        await subscriptionExpect(.outcomeUnknown) { try await client.unsubscribe(subscriptionID: id) }
        channel.result = nil
        // A correlated wire unknown settles its operation; only the alias is
        // quarantined. It must not poison a later independent invocation.
        #expect(try await client.invoke(channel.invocation(), grant: grant).payload == Data([9]))
        await subscriptionExpect(.outcomeUnknown) { _ = try await client.subscribe(requirementID: "requirement", grant: grant) }
        #expect(channel.sequences == [1, 2, 3, 4])
        await client.close()
    }

    @Test func preCancelledControlDoesNotSendAndSequenceNeverWraps() async throws {
        let channel = SubscriptionSDKChannel()
        let exchange = try ServiceConnectionExchange(channel: channel, lastSequence: UInt64.max - 1)
        let request = try ServiceControlRequest(requestID: UUID(), action: .subscribe(requirementID: "requirement", grantID: UUID()))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await exchange.control(request)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled operation sent") } catch { #expect(error is CancellationError) }
        #expect(channel.sequences.isEmpty)
        _ = try await exchange.control(request)
        await subscriptionExpect(.sessionRevoked) { _ = try await exchange.invoke(grantID: UUID(), invocation: channel.invocation()) }
        #expect(channel.sequences == [UInt64.max])
        await exchange.close()
    }

    @Test(arguments: [false, true])
    func exposedCancelAndCloseJoinOnePhysicalDrain(control: Bool) async throws {
        let channel = SubscriptionSDKChannel()
        let exchange = try ServiceConnectionExchange(channel: channel)
        let gate = SubscriptionSDKGate()
        channel.gate = gate
        let work = Task {
            if control {
                _ = try await exchange.control(ServiceControlRequest(requestID: UUID(), action: .unsubscribe(subscriptionID: UUID())))
            } else { _ = try await exchange.invoke(grantID: UUID(), invocation: channel.invocation()) }
        }
        await gate.waitForArrival()
        work.cancel()
        let close = Task { await exchange.close() }
        await channel.closing.waitForArrival()
        await subscriptionExpect(.sessionRevoked) { _ = try await exchange.control(ServiceControlRequest(requestID: UUID(), action: .unsubscribe(subscriptionID: UUID()))) }
        #expect(channel.closeCount == 1)
        await gate.release()
        do { try await work.value; Issue.record("Exposed cancellation returned success") } catch { #expect((error as? AddonFailure)?.code == .outcomeUnknown) }
        await close.value
        #expect(channel.closeCount == 1)
    }

    @Test func earlyEventRequiresConfirmedAliasAndExactGrantSnapshot() async throws {
        let channel = SubscriptionSDKChannel()
        let observed = SubscriptionSDKGate()
        let client = try TransportServiceClient(channel: channel, owner: channel.owner, handleEvent: { _ in await observed.arrive() })
        let grant = try channel.grant()
        channel.earlyEvent = try ServiceEvent(subscriptionID: channel.alias, token: grant, response: channel.response())
        _ = try await client.subscribe(requirementID: "requirement", grant: grant)
        await observed.waitForArrival()
        let foreign = try ServiceEvent(subscriptionID: UUID(), token: grant, response: channel.response())
        await subscriptionExpect(.permissionDenied) { try await channel.emit(foreign) }
        let changed = try Grant(id: grant.id, owner: grant.owner, serviceID: grant.serviceID, scope: grant.scope,
            expiresAt: grant.expiresAt.addingTimeInterval(1), generation: grant.generation, cost: grant.cost)
        let altered = try ServiceEvent(subscriptionID: channel.alias, token: changed, response: channel.response())
        await subscriptionExpect(.permissionDenied) { try await channel.emit(altered) }
        let stale = try Grant(id: grant.id, owner: grant.owner, serviceID: grant.serviceID, scope: grant.scope,
            expiresAt: grant.expiresAt, generation: ConnectionGeneration(), cost: grant.cost)
        let staleEvent = try ServiceEvent(subscriptionID: channel.alias, token: stale, response: channel.response())
        await subscriptionExpect(.permissionDenied) { try await channel.emit(staleEvent) }
        await client.close()
        let late = try ServiceEvent(subscriptionID: channel.alias, token: grant, response: channel.response())
        await subscriptionExpect(.sessionRevoked) { try await channel.emit(late) }
    }
}

private func subscriptionExpect(_ code: AddonFailure.Code, _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(code)") }
    catch { #expect((error as? AddonFailure)?.code == code) }
}

private actor SubscriptionSDKGate {
    private var arrived = false
    private var open = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func arrive() { arrived = true; arrival?.resume(); arrival = nil }
    func waitForArrival() async { if !arrived { await withCheckedContinuation { arrival = $0 } } }
    func pause() async { arrive(); if !open { await withCheckedContinuation { continuations.append($0) } } }
    func release() { open = true; let all = continuations; continuations.removeAll(); for continuation in all { continuation.resume() } }
}

private actor SubscriptionSDKObservation {
    private(set) var payload: Data?
    func record(_ value: Data) { payload = value }
}

/// SubscriptionSDKChannel is a controlled wire boundary only: assertions target real
/// shared SDK arbitration. Runtime/governor/receipt behavior is exercised separately
/// through the real host.
private final class SubscriptionSDKChannel: AddonServiceMessageChannel, @unchecked Sendable {
    let owner = AddonID(rawValue: "com.example.consumer")!
    let alias = UUID()
    private let lock = NSLock()
    private var currentGeneration = ConnectionGeneration()
    private var sequenceValues: [UInt64] = []
    private var closes = 0
    private var receiver: (@Sendable (Data) async throws -> Void)?
    private var heldResult: ServiceControlResult?
    private var heldGate: SubscriptionSDKGate?
    private var heldEvent: ServiceEvent?
    private var damaged = false
    private var rejected = false
    private var drift = false
    let closing = SubscriptionSDKGate()
    var generation: ConnectionGeneration { lock.withLock { currentGeneration } }
    var invocationProfile: ServiceInvocationFrameProfile? { .v1_3 }
    var subscriptionProfile: ServiceSubscriptionFrameProfile? { .v1_4 }
    var sequences: [UInt64] { lock.withLock { sequenceValues } }
    var closeCount: Int { lock.withLock { closes } }
    var gate: SubscriptionSDKGate? { get { lock.withLock { heldGate } } set { lock.withLock { heldGate = newValue } } }
    var result: ServiceControlResult? { get { lock.withLock { heldResult } } set { lock.withLock { heldResult = newValue } } }
    var earlyEvent: ServiceEvent? { get { lock.withLock { heldEvent } } set { lock.withLock { heldEvent = newValue } } }
    var damage: Bool { get { lock.withLock { damaged } } set { lock.withLock { damaged = newValue } } }
    var rejectBeforeHandoff: Bool { get { lock.withLock { rejected } } set { lock.withLock { rejected = newValue } } }
    var driftAfterExchange: Bool { get { lock.withLock { drift } } set { lock.withLock { drift = newValue } } }
    func grant() throws -> Grant {
        try Grant(id: UUID(), owner: owner, serviceID: "service", scope: ServiceScope(featureID: "main", operation: "read"),
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000), generation: generation,
            cost: AddonResourceRequest(profile: .eventDriven, requestedMemoryMiB: 0, maximumConcurrentWork: 1, background: .none))
    }
    func invocation() throws -> ServiceInvocation {
        try ServiceInvocation(schemaVersion: 1, requestID: UUID(), contractID: "service", operation: "read", payload: Data([1]), deadline: Date(timeIntervalSince1970: 2_000_000_000))
    }
    func response() throws -> ServiceResponse { try ServiceResponse(schemaVersion: 1, contractID: "service", operation: "read", payload: Data([9])) }
    func bindServiceEvents(_ receiver: @escaping @Sendable (Data) async throws -> Void) throws {
        try lock.withLock { guard self.receiver == nil else { throw AddonFailure(code: .resourceDenied, reason: "Already bound") }; self.receiver = receiver }
    }
    func emit(_ event: ServiceEvent) async throws {
        let receiver = lock.withLock { self.receiver }
        try await receiver?(ServiceSubscriptionFrameCodec.encode(event, profile: .v1_4))
    }
    func exchange(_ frame: Data, kind: AddonServiceMessageKind, sequence: UInt64) async throws -> AddonServiceMessageExchangeResult {
        lock.withLock { sequenceValues.append(sequence) }
        if let gate { await gate.pause() }
        if rejectBeforeHandoff { return .rejectedBeforeHandoff }
        if let earlyEvent { try await emit(earlyEvent) }
        if driftAfterExchange { lock.withLock { currentGeneration = ConnectionGeneration() } }
        if damage { return .response(Data("{}".utf8)) }
        switch kind {
        case .invocation:
            let request = try ServiceFrameCodec.decodeInvocationRequest(frame, profile: .v1_3)
            return .response(try ServiceFrameCodec.encode(ServiceInvocationReply(requestID: request.invocation.requestID,
                contractID: request.invocation.contractID, operation: request.invocation.operation, result: .completed(response())), profile: .v1_3))
        case .control:
            let request = try ServiceSubscriptionFrameCodec.decodeControlRequest(frame, profile: .v1_4)
            let value = result ?? (request.kind == .subscribe ? .subscribed(alias) : .acknowledged)
            return .response(try ServiceSubscriptionFrameCodec.encode(ServiceControlReply(requestID: request.requestID,
                kind: request.kind, phase: .terminal, result: value), profile: .v1_4))
        }
    }
    func close() async { lock.withLock { closes += 1 }; await closing.arrive(); if let gate { await gate.pause() } }
}

private func subscriptionNextPayload(_ stream: AsyncStream<Data>) async -> Data? {
    await withTaskGroup(of: Data?.self) { group in
        group.addTask { var iterator = stream.makeAsyncIterator(); return await iterator.next() }
        group.addTask { try? await Task.sleep(for: .seconds(5)); return nil }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
