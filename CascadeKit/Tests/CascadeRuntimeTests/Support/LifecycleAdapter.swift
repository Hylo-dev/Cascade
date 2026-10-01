//
//  LifecycleAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// LifecycleAdapter shares one lock for all access to adjacent recording support, including
/// runtime callbacks and inspection/staging from the test task. No mutable state of that
/// adapter escapes the wrapper.
final class LifecycleAdapter: AddonRuntimeAdapter, @unchecked Sendable {

    private let lock   = NSLock()
    private let target = RecordingRuntimeAdapter()
    private var live  : Set<RuntimeIncarnation> = []

    var incarnations: [RuntimeIncarnation] { lock.withLock { Array(live) } }

    var providerStart: RuntimeStartDelivery? {
        lock.withLock {
            guard let owner = AddonID(rawValue: "com.example.focus.cascade") else { return nil }

            return target.lastStart(owner: owner)
        }
    }

    var serviceCount: Int { lock.withLock { target.serviceDeliveryCount } }

    var serviceRequestID: UUID? {
        lock.withLock {
            for incarnation in live {
                if case .service(let work) = target.currentDelivery(incarnation: incarnation) {
                    return work.invocation.requestID
                }
            }

            return nil
        }
    }

    var hasIngress: Bool { lock.withLock { live.contains { target.hasIngress(incarnation: $0) } } }

    var hasPayload: Bool {
        lock.withLock {
            live.contains {
                target.hasIngress(incarnation: $0) || target.currentDelivery(incarnation: $0) != nil
            }
        }
    }

    func stage(
        _ completion: InvocationCompletion,
        incarnation : RuntimeIncarnation
    ) throws -> RuntimeIngressHandle? {
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : completion,
            checkpoint   : nil
        )

        return lock.withLock { target.stageIngress(output, incarnation: incarnation) }
    }

    func takeIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> ProviderOutput? {
        lock.withLock { target.takeIngress(handle, incarnation: incarnation) }
    }

    func rejectIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        lock.withLock { target.rejectIngress(handle, incarnation: incarnation) }
    }

    func cancelIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        lock.withLock { target.cancelIngress(handle, incarnation: incarnation) }
    }

    func finishIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) {
        lock.withLock { target.finishIngress(handle, incarnation: incarnation) }
    }

    func tryHandoff(
        incarnation: RuntimeIncarnation,
        delivery   : RuntimeAdapterDelivery
    ) -> RuntimeHandoffResult {
        lock.withLock {
            let result = target.tryHandoff(incarnation: incarnation, delivery: delivery)
            if result == .accepted, case .start = delivery { live.insert(incarnation) }

            return result
        }
    }

    func requestStop(
        incarnation: RuntimeIncarnation,
        reason     : RuntimeStopReason
    ) {
        lock.withLock { target.requestStop(incarnation: incarnation, reason: reason) }
    }

    func deliveryWasReceived(incarnation: RuntimeIncarnation) {
        lock.withLock { target.deliveryWasReceived(incarnation: incarnation) }
    }

    func processDidExit(incarnation: RuntimeIncarnation) {
        lock.withLock {
            target.processDidExit(incarnation: incarnation)
            live.remove(incarnation)
        }
    }
}
