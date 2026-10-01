//
//  ServiceInvocationLifecycleIntegrationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// ServiceInvocationLifecycleIntegrationTests exercises the actual runtime/broker composition.
/// Identities, consent and observeExit are modeled test inputs; this suite makes no claim about
/// signatures, external service wire traffic or physical process exit.
@Suite(.timeLimit(.minutes(1)))
struct ServiceInvocationLifecycleIntegrationTests {

    @Test(arguments: [false, true])
    func canonicalCompletionSeparatesHostKnownFromLocalUnknown(cancelFirst: Bool) async throws {
        try await withLifecycleHost { host in
            let ledger = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            #expect(host.acquisition.grant.generation != host.consumer.publicationConnection.generation)
            let request = try host.invocation()
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            let work = try await host.admit(request)
            #expect(try await host.runtime.pumpServiceInvocation(work.id))
            #expect(host.adapter.serviceRequestID == request.requestID)
            #expect(host.adapter.serviceCount == 1)
            #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil)
            let paidMemory = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
            if cancelFirst {
                #expect(ledger.cancel(ticket)?.failure == .outcomeUnknown)
                #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) == paidMemory)
                #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
                #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
            }

            let response = try host.response()
            let result   = try await host.complete(requestID: request.requestID, response: response)
            guard case .committed = result else {
                Issue.record("Canonical response was not accepted")
                return
            }

            let relayed = try await host.knownCompletion(requestID: request.requestID)
            #expect(
                try ledger.consume(
                    relayed,
                    ticket    : ticket,
                    generation: host.acquisition.grant.generation
                )
                    == (cancelFirst ? .discardCancelled : .deliver)
            )
            #expect(ledger.cancel(ticket) == nil && ledger.close() == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
            #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) >= lifecycleTestBytes)
            #expect(!host.adapter.hasPayload)
            // Host-only negative probe after ledger closure: no prepared SDK ticket or local
            // cancellation claim. Canonical history prevents a second provider dispatch.
            await lifecycleIntegrationFailure(.invalidPayload) { _ = try await host.admit(request) }
            #expect(host.adapter.serviceCount == 1)
        }
    }

    @Test
    func pendingCanonicalCompletionWaitsForActualDrainAndRetainsAccounting() async throws {
        try await withLifecycleHost { host in
            let ledger  = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request = try host.invocation()
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            let work = try await host.admit(request)
            #expect(try await host.runtime.pumpServiceInvocation(work.id))
            let response = try host.response()
            try await host.withHeldAdmission { () async throws -> Void in
                #expect(
                    try await host.complete(requestID: request.requestID, response: response)
                        == .pendingServiceCompletion
                )
                await lifecycleIntegrationFailure(.resourceDenied) {
                    _ = try await host.knownCompletion(requestID: request.requestID)
                }

                #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
                #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
                let beforeCancel = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
                #expect(ledger.cancel(ticket)?.failure == .outcomeUnknown)
                #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) == beforeCancel)
                #expect(host.adapter.hasIngress)
                // No pending receipt is ever presented to consume as a completion.
            }

            #expect(
                try ledger.consume(
                    try await host.knownCompletion(requestID: request.requestID),
                    ticket    : ticket,
                    generation: host.acquisition.grant.generation
                ) == .discardCancelled
            )
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
            #expect(!host.adapter.hasPayload)
        }
    }

    @Test(arguments: [false, true])
    func dispatchedRevocationRefusesLateResultWithoutPrematureRefund(closeLocally: Bool) async throws {
        try await withLifecycleHost { host in
            let ledger  = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request = try host.invocation()
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            let work = try await host.admit(request)
            #expect(try await host.runtime.pumpServiceInvocation(work.id))
            let memoryBeforeLocalOutcome = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
            if closeLocally {
                #expect(ledger.close()?.failure == .outcomeUnknown)
            } else {
                #expect(ledger.cancel(ticket)?.failure == .outcomeUnknown)
            }

            #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) == memoryBeforeLocalOutcome)
            let response = try host.response()
            let ingress  = try #require(
                try host.adapter.stage(
                    .service(requestID: request.requestID, response: response),
                    incarnation: host.provider.incarnation
                )
            )
            try await host.withHeldAdmission(expectRevoked: true) { () async throws -> Void in
                #expect(
                    try await host.runtime.receivePublicationOutput(
                        ingress,
                        connection: host.provider,
                        sequence  : 1
                    ) == .pendingServiceCompletion
                )
                await host.runtime.disable(owner: host.owner)
            }

            #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
            #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
            await lifecycleIntegrationFailure(.sessionRevoked) {
                _ = try await host.knownCompletion(requestID: request.requestID)
            }
            // A stale provider connection cannot accept another canonical completion.
            await lifecycleIntegrationFailure(.sessionRevoked) {
                _ = try await host.runtime.receivePublicationOutput(
                    ingress,
                    connection: host.provider,
                    sequence  : 2
                )
            }

            #expect(ledger.cancel(ticket) == nil && ledger.close() == nil)
            // Explicit modeled cleanup input, never inferred from local close or adapter stop.
            await host.runtime.observeExit(host.provider.incarnation)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
            #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) >= lifecycleTestBytes)
        }
    }

    @Test(arguments: [false, true])
    func predispatchCloseOrExpiryRetiresRealUnsentWork(expire: Bool) async throws {
        try await withLifecycleHost { host in
            let ledger  = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request = try host.invocation()
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            // Runtime admission may expose the request to the host; mark attempting before
            // that suspension. Provider non-dispatch alone cannot prove SDK request non-exposure.
            try ledger.beginHandoff(ticket)
            let work = try await host.admit(request)
            if expire {
                host.clock.advance(seconds: 21)
                await lifecycleIntegrationFailure(.deadlineExceeded) {
                    _ = try await host.runtime.pumpServiceInvocation(work.id)
                }

                #expect(
                    try await host.runtime.serviceOutcome(
                        connection: host.consumer,
                        grantID   : host.acquisition.grant.id,
                        requestID : request.requestID
                    ) == .unsent
                )
                #expect(ledger.cancel(ticket)?.failure == .outcomeUnknown)
            } else {
                await host.runtime.closeConnection(host.consumer)
                #expect(try await host.runtime.pumpServiceInvocation(work.id) == false)
                #expect(ledger.close()?.failure == .outcomeUnknown)
            }

            #expect(host.adapter.serviceCount == 0)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
            #expect(ledger.close() == nil)
        }
    }

    @Test
    func preparedCancellationNeverAdmitsHostWork() async throws {
        try await withLifecycleHost { host in
            let ledger = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let ticket = try ledger.begin(host.invocation(), grantID: host.acquisition.grant.id)
            #expect(ledger.cancel(ticket)?.failure == .cancelled)
            #expect(host.adapter.serviceCount == 0)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
        }
    }

    @Test
    func canonicalWrongCorrelationPreservesRealWorkAndLedger() async throws {
        try await withLifecycleHost { host in
            let ledger  = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request = try host.invocation()
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            let work = try await host.admit(request)
            #expect(try await host.runtime.pumpServiceInvocation(work.id))
            await lifecycleIntegrationFailure(.sessionRevoked) {
                _ = try await host.complete(requestID: UUID(), response: host.response())
            }

            #expect(host.adapter.serviceRequestID == request.requestID)
            #expect(
                try await host.runtime.serviceOutcome(
                    connection: host.consumer,
                    grantID   : host.acquisition.grant.id,
                    requestID : request.requestID
                ) == .dispatched
            )
            #expect(
                try await host.complete(
                    requestID: request.requestID,
                    response : host.response(),
                    sequence : 1
                )
                    != .pendingServiceCompletion
            )
            #expect(
                try ledger.consume(
                    try await host.knownCompletion(requestID: request.requestID),
                    ticket    : ticket,
                    generation: host.acquisition.grant.generation
                ) == .deliver
            )
        }
    }

    @Test
    func freshCanonicalServiceGenerationDoesNotReviveOldTicket() async throws {
        try await withLifecycleHost { host in
            let oldLedger = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request   = try host.invocation()
            let oldTicket = try oldLedger.begin(request, grantID: host.acquisition.grant.id)
            try oldLedger.beginHandoff(oldTicket)
            let oldWork = try await host.admit(request)
            #expect(try await host.runtime.pumpServiceInvocation(oldWork.id))
            #expect(oldLedger.close()?.failure == .outcomeUnknown)
            await host.runtime.closeConnection(host.consumer)
            await host.runtime.observeExit(host.consumer.incarnation)
            await host.runtime.observeExit(host.provider.incarnation)
            let fresh = try await host.reconnect()
            do {
                #expect(fresh.grant.generation != host.acquisition.grant.generation)
                #expect(fresh.grant.generation != fresh.consumer.publicationConnection.generation)
                let replayLedger = ServiceInvocationLifecycle(generation: fresh.grant.generation)
                let replayTicket = try replayLedger.begin(request, grantID: fresh.grant.id)
                #expect(
                    try await host.runtime.serviceOutcome(
                        connection: fresh.consumer,
                        grantID   : fresh.grant.id,
                        requestID : request.requestID
                    ) == .unknown
                )
                // Broker retention prevents redispatch, but admission still exposes the request
                // to the host. Its rejection cannot establish request-side non-exposure.
                try replayLedger.beginHandoff(replayTicket)
                await lifecycleIntegrationFailure(.invalidPayload) {
                    _ = try await host.runtime.beginServiceInvocation(
                        connection: fresh.consumer,
                        grantID   : fresh.grant.id,
                        invocation: request
                    )
                }

                #expect(host.adapter.serviceCount == 1)
                #expect(replayLedger.cancel(replayTicket)?.failure == .outcomeUnknown)
                let nextRequest = try host.invocation()
                await lifecycleIntegrationFailure(.resourceDenied) {
                    _ = try replayLedger.begin(nextRequest, grantID: fresh.grant.id)
                }

                #expect(replayLedger.cancel(replayTicket) == nil)
                #expect(replayLedger.close() == nil)
                #expect(replayLedger.close() == nil)
                await lifecycleIntegrationFailure(.sessionRevoked) {
                    _ = try replayLedger.begin(nextRequest, grantID: fresh.grant.id)
                }
                // A distinct ledger owns the new invocation; closing the replay ledger neither
                // retracts host exposure nor releases the independently prepaid buffer scope.
                let ledger = ServiceInvocationLifecycle(generation: fresh.grant.generation)
                let ticket = try ledger.begin(nextRequest, grantID: fresh.grant.id)
                try ledger.beginHandoff(ticket)
                await lifecycleIntegrationFailure(.sessionRevoked) {
                    _ = try ledger.consume(
                        .service(requestID: request.requestID, response: host.response()),
                        ticket    : oldTicket,
                        generation: host.acquisition.grant.generation
                    )
                }

                let work = try await host.runtime.beginServiceInvocation(
                    connection: fresh.consumer,
                    grantID   : fresh.grant.id,
                    invocation: nextRequest
                )
                #expect(try await host.runtime.pumpServiceInvocation(work.id))
                let response = try host.response()
                let ingress  = try #require(
                    try host.adapter.stage(
                        .service(requestID: nextRequest.requestID, response: response),
                        incarnation: fresh.provider.incarnation
                    )
                )
                guard
                    case .committed = try await host.runtime.receivePublicationOutput(
                        ingress,
                        connection: fresh.provider,
                        sequence  : 1
                    )
                else {
                    throw AddonFailure(code: .resourceDenied, reason: "Fresh completion pending")
                }

                guard
                    case .completed(let known) = try await host.runtime.serviceOutcome(
                        connection: fresh.consumer,
                        grantID   : fresh.grant.id,
                        requestID : nextRequest.requestID
                    )
                else {
                    throw AddonFailure(code: .resourceDenied, reason: "No fresh known outcome")
                }

                #expect(
                    try ledger.consume(
                        .service(requestID: nextRequest.requestID, response: known),
                        ticket    : ticket,
                        generation: fresh.grant.generation
                    ) == .deliver
                )
                #expect(host.adapter.serviceCount == 2)
            } catch {
                await host.runtime.closeConnection(fresh.consumer)
                await host.runtime.observeExit(fresh.consumer.incarnation)
                await host.runtime.observeExit(fresh.provider.incarnation)
                throw error
            }

            await host.runtime.closeConnection(fresh.consumer)
            await host.runtime.observeExit(fresh.consumer.incarnation)
            await host.runtime.observeExit(fresh.provider.incarnation)
        }
    }

    @Test
    func thrownGatedBodyJoinsAdmissionBeforeNextRealInvocation() async throws {
        try await withLifecycleHost { host in
            await lifecycleIntegrationFailure(.invalidPayload) {
                try await host.withHeldAdmission {
                    throw AddonFailure(code: .invalidPayload, reason: "Explicit test cleanup input")
                }
            }

            let ledger  = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request = try host.invocation()
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            let work = try await host.admit(request)
            #expect(try await host.runtime.pumpServiceInvocation(work.id))
            _ = try await host.complete(requestID: request.requestID, response: host.response())
            #expect(
                try ledger.consume(
                    try await host.knownCompletion(requestID: request.requestID),
                    ticket    : ticket,
                    generation: host.acquisition.grant.generation
                ) == .deliver
            )
        }
    }

    @Test
    func maximumIdentifierMetadataUsesExistingSemanticBounds() async throws {
        try await withLifecycleHost { host in
            let ledger    = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let contract  = String(repeating: "a", count: 128)
            let operation = String(repeating: "b", count: 128)
            let request   = try host.invocation(
                bytes    : 0,
                contract : contract,
                operation: operation
            )
            let ticket = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            let response = try ServiceResponse(
                schemaVersion: 1,
                contractID   : contract,
                operation    : operation,
                payload      : Data()
            )
            #expect(
                try ledger.consume(
                    .service(requestID: request.requestID, response: response),
                    ticket    : ticket,
                    generation: host.acquisition.grant.generation
                ) == .deliver
            )
        }
    }

    @Test(arguments: [0, 65_536])
    func maximumTypedValuesAndExternalDecodeFailureKeepLedgerValid(bytes: Int) async throws {
        try await withLifecycleHost { host in
            let ledger  = ServiceInvocationLifecycle(generation: host.acquisition.grant.generation)
            let request = try host.invocation(bytes: bytes)
            let ticket  = try ledger.begin(request, grantID: host.acquisition.grant.id)
            try ledger.beginHandoff(ticket)
            // Validation is at the supported constructors and decoder, never an invalid typed hook.
            await lifecycleIntegrationFailure(.invalidPayload) {
                _ = try host.invocation(bytes: 65_537)
            }

            await lifecycleIntegrationFailure(.invalidPayload) {
                _ = try host.invocation(contract: String(repeating: "a", count: 129))
            }

            await lifecycleIntegrationFailure(.invalidPayload) {
                _ = try host.invocation(operation: "!")
            }

            await lifecycleIntegrationFailure(.invalidPayload) {
                _ = try host.invocation(deadline: Date(timeIntervalSince1970: .infinity))
            }

            let badWire = Data(
                "{\"service\":{\"requestID\":\"\(request.requestID.uuidString)\",\"response\":{\"schemaVersion\":2,\"contractID\":\"com.example.focus.sessions\",\"operation\":\"read\",\"payload\":\"\"}}}"
                    .utf8
            )
            await lifecycleIntegrationFailure(.invalidPayload) {
                _ = try JSONDecoder().decode(InvocationCompletion.self, from: badWire)
            }

            let response = try host.response(bytes: bytes)
            #expect(
                try ledger.consume(
                    .service(requestID: request.requestID, response: response),
                    ticket    : ticket,
                    generation: host.acquisition.grant.generation
                ) == .deliver
            )
            #expect(response.payload.count == bytes)
            #expect(host.adapter.serviceCount == 0)
        }
    }
}

private let lifecycleTestBytes = 1_048_576

func lifecycleIntegrationFailure(
    _ code: AddonFailure.Code,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("Expected \(code)")
    } catch let failure as AddonFailure {
        #expect(failure.code == code, "Actual: \(failure)")
    } catch { Issue.record("Expected AddonFailure \(code), got \(error)") }
}

/// withLifecycleHost independently prepays fixture, SDK input/response and temporary encoding
/// before any Data creation.
/// The protected scope returns only Void; host work is joined and all retained buffers drained first.
private func withLifecycleHost(_ body: @Sendable (LifecycleHost) async throws -> Void) async throws {
    let governor = ResourceGovernor()
    let owner    = try #require(AddonID(rawValue: "com.example.consumer"))
    try await governor.withAssetDecodeReservation(bytes: lifecycleTestBytes, owner: owner) {
        let host = try await LifecycleHost.make(governor: governor)
        do {
            try await body(host)
        } catch {
            await host.cleanup()
            throw error
        }

        await host.cleanup()
        #expect(!host.adapter.hasPayload)
    }

    #expect(await governor.usage(.admittedMemoryBytes, owner: owner) == 0)
}
