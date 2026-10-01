//
//  GatedRuntimeServiceDecisionAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadeRuntime

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
