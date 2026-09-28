//
//  AddonRuntimeTestSupport.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadeRuntime

/// GatedRuntimeResourceAccess withholds one post-resize return after forwarding the
/// real governor mutation exactly once. It never fabricates reservations or outcomes.
actor GatedRuntimeResourceAccess: RuntimeResourceAccess {
    nonisolated let resourceGovernorTarget: ResourceGovernor
    private var shouldGateRelease = false
    private var shouldGateResize = false
    private var shouldGateReduction = false
    private var shouldGateTemporaryMemory = false
    private var shouldGateStateAdmission = false
    private var shouldGateJobAdmission = false
    private var hasArrived = false
    private var isReleased = false
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(target: ResourceGovernor) {
        resourceGovernorTarget = target
    }

    /// armRelease holds one real refund return after its canonical governor mutation.
    func armRelease() {
        shouldGateRelease = true
        hasArrived = false
        isReleased = false
    }

    func armResize() {
        shouldGateResize = true
        hasArrived = false
        isReleased = false
    }

    func armReduction() {
        shouldGateReduction = true
        hasArrived = false
        isReleased = false
    }

    func armTemporaryMemory() {
        shouldGateTemporaryMemory = true
        hasArrived = false
        isReleased = false
    }

    func armStateAdmission() {
        shouldGateStateAdmission = true
        hasArrived = false
        isReleased = false
    }

    func armJobAdmission() {
        shouldGateJobAdmission = true
        hasArrived = false
        isReleased = false
    }

    func waitForArrival() async {
        if hasArrived || isReleased { return }
        await withCheckedContinuation { continuation in
            arrivalContinuation = continuation
        }
    }

    func releaseGate() {
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func waitForRelease() async {
        if isReleased { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        } onCancel: {
            Task { await self.releaseGate() }
        }
    }

    private func reportTerminalArrival() {
        hasArrived = true
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let shouldGate: Bool
        switch request {
        case .temporaryMemory where shouldGateTemporaryMemory:
            shouldGateTemporaryMemory = false
            shouldGate = true
        case .state where shouldGateStateAdmission:
            shouldGateStateAdmission = false
            shouldGate = true
        case .job where shouldGateJobAdmission:
            shouldGateJobAdmission = false
            shouldGate = true
        default:
            shouldGate = false
        }
        let reservation: ResourceReservation
        do {
            reservation = try await resourceGovernorTarget.admit(
                request,
                owner: owner
            )
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }
        guard shouldGate else { return reservation }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return reservation }
        await waitForRelease()
        return reservation
    }

    func release(
        _ reservationID: UUID,
        owner           : AddonID
    ) async throws {
        let shouldGate = shouldGateRelease
        shouldGateRelease = false
        try await resourceGovernorTarget.release(
            reservationID,
            owner: owner
        )
        guard shouldGate else { return }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await waitForRelease()
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        toBytes bytes   : Int
    ) async -> Bool {
        let shouldGate = shouldGateReduction
        shouldGateReduction = false
        let result = await resourceGovernorTarget.reduceStateReservation(
            reservationID,
            owner  : owner,
            toBytes: bytes
        )
        guard shouldGate else { return result }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }

    func resizeStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        let shouldGate = shouldGateResize
        shouldGateResize = false
        let result: Bool
        do {
            result = try await resourceGovernorTarget.resizeStateReservation(
                reservationID,
                owner    : owner,
                fromBytes: fromBytes,
                toBytes  : toBytes
            )
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }
        guard shouldGate else { return result }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }
    func resizeDiskReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }

}

/// RuntimeServiceDecisionAccessBox exposes the wrapper assembled around the runtime's private broker.
final class RuntimeServiceDecisionAccessBox: @unchecked Sendable {
    var access: GatedRuntimeServiceDecisionAccess?
}

/// GatedRuntimeServiceDecisionAccess withholds one post-consume return after forwarding
/// the real private-broker decision exactly once.
actor GatedRuntimeServiceDecisionAccess: RuntimeServiceDecisionAccess {
    nonisolated let serviceBrokerTarget: ServiceBroker
    private var shouldGateInvocation = false
    private var shouldGateSource = false
    private var shouldGateDeadline = false
    private var shouldGateCompletionPreparation = false
    private var gateBeforeCompletionPreparation = false
    private var hasArrived = false
    private var isReleased = false
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(target: ServiceBroker) {
        serviceBrokerTarget = target
    }

    func armInvocation() {
        shouldGateInvocation = true
        hasArrived = false
        isReleased = false
    }

    func armSource() {
        shouldGateSource = true
        hasArrived = false
        isReleased = false
    }

    func armDeadline() {
        shouldGateDeadline = true
        hasArrived = false
        isReleased = false
    }

    /// armCompletionPreparation parks one real preparation before invocation or after its successful return.
    func armCompletionPreparation(beforePreparation: Bool = false) {
        shouldGateCompletionPreparation = true
        gateBeforeCompletionPreparation = beforePreparation
        hasArrived = false
        isReleased = false
    }

    func waitForArrival() async {
        if hasArrived || isReleased { return }
        await withCheckedContinuation { continuation in
            arrivalContinuation = continuation
        }
    }

    func releaseGate() {
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func waitForRelease() async {
        if isReleased { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        } onCancel: {
            Task { await self.releaseGate() }
        }
    }

    private func reportTerminalArrival() {
        hasArrived = true
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func consumeInvocation(
        _ id: UUID,
        now : RuntimeInstant
    ) async throws -> UUID {
        let shouldGate = shouldGateInvocation
        shouldGateInvocation = false
        let result: UUID
        do {
            result = try await serviceBrokerTarget.consumeInvocation(
                id,
                now: now
            )
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }
        guard shouldGate else { return result }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }

    func consumeSourceStart(
        _ id: UUID,
        now : RuntimeInstant
    ) async throws -> ServiceSourceDescriptor {
        let shouldGate = shouldGateSource
        shouldGateSource = false
        let result: ServiceSourceDescriptor
        do {
            result = try await serviceBrokerTarget.consumeSourceStart(
                id,
                now: now
            )
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }
        guard shouldGate else { return result }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }

    func prepareInvocationCompletion(
        _ id       : UUID,
        response   : ServiceResponse,
        receivedAt : RuntimeInstant
    ) async throws -> ServiceBroker.CompletionPreparation {
        let shouldGate = shouldGateCompletionPreparation
        shouldGateCompletionPreparation = false
        let gateBefore = gateBeforeCompletionPreparation
        gateBeforeCompletionPreparation = false
        if shouldGate, gateBefore {
            hasArrived = true
            arrivalContinuation?.resume()
            arrivalContinuation = nil
            if !isReleased { await waitForRelease() }
        }
        let result: ServiceBroker.CompletionPreparation
        do {
            result = try await serviceBrokerTarget.prepareInvocationCompletion(
                id,
                response  : response,
                receivedAt: receivedAt
            )
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }
        guard shouldGate, !gateBefore else { return result }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }

    func nextDeadline() async -> Duration? {
        let shouldGate = shouldGateDeadline
        shouldGateDeadline = false
        let result = await serviceBrokerTarget.nextDeadline()
        guard shouldGate else { return result }
        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }
}
