//
//  ServiceInvocationExchangeTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

/// ServiceInvocationExchangeTests covers logical SDK arbitration, with a bounded
/// embedding scope. Real governor/adapter byte ownership and pressure are
/// exercised by CascadeRuntimeTests, not modeled here.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ServiceInvocationExchangeTests {

    @Test(arguments: [0, 65_536])
    func completedThenRefusedAndUnknownPermitNewOperation(bytes: Int) async throws {
        try await withSDKExchange { channel, executor in
            let invocation = try sdkInvocation(bytes: bytes)
            let response   = try sdkResponse(bytes: bytes)
            channel.result = .completed(response)
            #expect(try await executor.invoke(grantID: UUID(), invocation: invocation) == .completed(response))

            channel.result = .refused(code: .permissionDenied, reason: "denied")
            guard case .refused(let code, _) = try await executor.invoke(
                grantID   : UUID(),
                invocation: sdkInvocation()
            ) else {
                Issue.record("Expected refusal")
                return
            }
            #expect(code == .permissionDenied)

            channel.result = .outcomeUnknown
            #expect(try await executor.invoke(grantID: UUID(), invocation: sdkInvocation()) == .outcomeUnknown)

            channel.result = .completed(try sdkResponse())
            let actual   = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            let expected = ServiceInvocationResult.completed(try sdkResponse())
            #expect(actual == expected)
            #expect(channel.sequences == [1, 2, 3, 4])
        }
    }

    @Test(arguments: [
        SDKReplyDamage.outerID, .outerContract, .outerOperation, .nestedContract, .nestedOperation, .malformed
    ])
    func entireReplyValidationPrecedesProjectionAndPoisons(damage: SDKReplyDamage) async throws {
        try await withSDKExchange { channel, executor in
            channel.damage = damage
            await sdkExpect(.outcomeUnknown) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }
            #expect(channel.closeCount == 1)

            await sdkExpect(.sessionRevoked) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }
        }
    }

    @Test(arguments: [false, true])
    func refusedAndUnknownRequireWholeReplyCorrelation(unknown: Bool) async throws {
        try await withSDKExchange { channel, executor in
            channel.result = unknown ? .outcomeUnknown : .refused(code: .permissionDenied, reason: "denied")
            channel.damage = .outerID
            await sdkExpect(.outcomeUnknown) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }
            #expect(channel.closeCount == 1)

            await sdkExpect(.sessionRevoked) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }
        }
    }

    @Test(arguments: ["read", "write"])
    func unresolvedTransportHasUnknownEffectsForEveryOperation(operation: String) async throws {
        try await withSDKExchange { channel, executor in
            channel.transportThrows = true

            await sdkExpect(.outcomeUnknown) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation(operation: operation))
            }
        }
    }

    @Test
    func explicitRequestRejectionAllowsReuse() async throws {
        try await withSDKExchange { channel, executor in
            channel.rejectRequest = true
            await sdkExpect(.dependencyUnavailable) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }

            channel.rejectRequest = false
            let actual   = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            let expected = ServiceInvocationResult.completed(try sdkResponse())
            #expect(actual == expected)
        }
    }

    @Test
    func sequenceExhaustionDoesNotWrap() async throws {
        let channel  = SDKInvocationChannel()
        let executor = try ServiceInvocationExchange(channel: channel, lastSequence: UInt64.max - 1)

        do {
            _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            await sdkExpect(.sessionRevoked) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }
            #expect(channel.sequences == [UInt64.max])
        } catch {
            await executor.close()
            throw error
        }

        await executor.close()
    }

    @Test
    func cancelPreparedPreventsSendAndDoesNotPoison() async throws {
        try await withSDKExchange { channel, executor in
            let gate = SDKInvocationGate()
            let work = Task {
                try await ServiceInvocationExchange.$preparedObserver.withValue({ await gate.pause() }) {
                    try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
                }
            }

            await gate.wait()
            work.cancel()
            await gate.release()

            do {
                _ = try await work.value
                Issue.record("Expected cancellation")
            } catch {
                #expect(error is CancellationError)
            }
            #expect(channel.sequences.isEmpty)

            let actual   = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            let expected = ServiceInvocationResult.completed(try sdkResponse())
            #expect(actual == expected)
        }
    }

    @Test(arguments: [false, true])
    func cancelAndConsumeUseFirstLocalOutcome(cancelFirst: Bool) async throws {
        try await withSDKExchange { channel, executor in
            let gate = SDKInvocationGate()
            if cancelFirst { channel.exchangeGate = gate }

            let observer: (@Sendable () async -> Void)?
            if cancelFirst { observer = nil } else { observer = { await gate.pause() } }

            let work = Task {
                try await ServiceInvocationExchange.$consumedObserver.withValue(observer) {
                    try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
                }
            }

            await gate.wait()
            work.cancel()
            await gate.release()

            if cancelFirst {
                await sdkExpect(.outcomeUnknown) { _ = try await work.value }
            } else {
                let actual   = try await work.value
                let expected = ServiceInvocationResult.completed(try sdkResponse())
                #expect(actual == expected)
            }
        }
    }

    @Test
    func closeAfterConsumeSuppressesFinalDeliveryAndSharesDrain() async throws {
        try await withSDKExchange { channel, executor in
            let gate = SDKInvocationGate(), drainGate = SDKInvocationGate()
            channel.closeGate = drainGate

            let work = Task {
                try await ServiceInvocationExchange.$consumedObserver.withValue({ await gate.pause() }) {
                    try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
                }
            }

            await gate.wait()
            let firstClose = Task { await executor.close() }
            await drainGate.wait()
            let secondClose = Task { await executor.close() }
            await sdkExpect(.sessionRevoked) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }

            await gate.release()
            await drainGate.release()
            await firstClose.value
            await secondClose.value

            await sdkExpect(.sessionRevoked) { _ = try await work.value }
            #expect(channel.closeCount == 1)
        }
    }

    @Test
    func wholeOperationSlotRemainsOccupiedAfterConsume() async throws {
        try await withSDKExchange { _, executor in
            let gate = SDKInvocationGate()
            let work = Task {
                try await ServiceInvocationExchange.$consumedObserver.withValue({ await gate.pause() }) {
                    try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
                }
            }

            await gate.wait()
            await sdkExpect(.resourceDenied) {
                _ = try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
            }

            await gate.release()
            _ = try await work.value
        }
    }

    @Test(arguments: [false, true])
    func descriptorDriftBeforeAndAfterExposureFailsClosed(profileDrift: Bool) async throws {
        for beforeExposure in [false, true] {
            try await withSDKExchange { channel, executor in
                let gate = SDKInvocationGate()
                if !beforeExposure { channel.exchangeGate = gate }

                let observer: (@Sendable () async -> Void)?
                if beforeExposure { observer = { await gate.pause() } } else { observer = nil }

                let work = Task {
                    try await ServiceInvocationExchange.$preparedObserver.withValue(observer) {
                        try await executor.invoke(grantID: UUID(), invocation: sdkInvocation())
                    }
                }

                await gate.wait()
                if profileDrift { channel.withdrawProfile() } else { channel.replaceGeneration() }
                await gate.release()

                await sdkExpect(beforeExposure ? .sessionRevoked : .outcomeUnknown) { _ = try await work.value }
            }
        }
    }
}

private func withSDKExchange(
    _ body: @Sendable (SDKInvocationChannel, ServiceInvocationExchange) async throws -> Void
) async throws {
    // Source/codec/return lifetime is bounded here; quota enforcement is proved only
    // in runtime integration's protected ResourceGovernor scope. No buffers escape.
    let channel  = SDKInvocationChannel()
    let executor = try ServiceInvocationExchange(channel: channel)

    do {
        try await body(channel, executor)
    } catch {
        await executor.close()
        throw error
    }

    await executor.close()
}

private func sdkInvocation(
    bytes    : Int = 1,
    operation: String = "read"
) throws -> ServiceInvocation {
    try ServiceInvocation(
        schemaVersion: 1,
        requestID    : UUID(),
        contractID   : "com.example.service",
        operation    : operation,
        payload      : Data(repeating: 255, count: bytes),
        deadline     : Date(timeIntervalSince1970: 2_000)
    )
}

func sdkResponse(bytes: Int = 1) throws -> ServiceResponse {
    try ServiceResponse(
        schemaVersion: 1,
        contractID   : "com.example.service",
        operation    : "read",
        payload      : Data(repeating: 255, count: bytes)
    )
}

private func sdkExpect(
    _ code: AddonFailure.Code,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("Expected \(code)")
    } catch {
        #expect((error as? AddonFailure)?.code == code, "Actual: \(error)")
    }
}
