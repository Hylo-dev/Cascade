//
//  SubscriptionSDKChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

/// SubscriptionSDKChannel is a controlled wire boundary only: assertions target real
/// shared SDK arbitration. Runtime/governor/receipt behavior is exercised separately
/// through the real host.
final class SubscriptionSDKChannel: AddonServiceMessageChannel, @unchecked Sendable {

    let owner = AddonID(rawValue: "com.example.consumer")!
    let alias = UUID()

    private let lock              = NSLock()
    private var currentGeneration = ConnectionGeneration()
    private var sequenceValues   : [UInt64] = []
    private var closes            = 0
    private var receiver         : (@Sendable (Data) async throws -> Void)?
    private var heldResult       : ServiceControlResult?
    private var heldGate         : SubscriptionSDKGate?
    private var heldEvent        : ServiceEvent?
    private var damaged           = false
    private var rejected          = false
    private var drift             = false

    let closing = SubscriptionSDKGate()

    var generation         : ConnectionGeneration { lock.withLock { currentGeneration } }
    var invocationProfile  : ServiceInvocationFrameProfile? { .v1_3 }
    var subscriptionProfile: ServiceSubscriptionFrameProfile? { .v1_4 }
    var sequences          : [UInt64] { lock.withLock { sequenceValues } }
    var closeCount         : Int { lock.withLock { closes } }

    var gate: SubscriptionSDKGate? {
        get { lock.withLock { heldGate } }
        set { lock.withLock { heldGate = newValue } }
    }

    var result: ServiceControlResult? {
        get { lock.withLock { heldResult } }
        set { lock.withLock { heldResult = newValue } }
    }

    var earlyEvent: ServiceEvent? {
        get { lock.withLock { heldEvent } }
        set { lock.withLock { heldEvent = newValue } }
    }

    var damage: Bool {
        get { lock.withLock { damaged } }
        set { lock.withLock { damaged = newValue } }
    }

    var rejectBeforeHandoff: Bool {
        get { lock.withLock { rejected } }
        set { lock.withLock { rejected = newValue } }
    }

    var driftAfterExchange: Bool {
        get { lock.withLock { drift } }
        set { lock.withLock { drift = newValue } }
    }

    func grant() throws -> Grant {
        try Grant(
            id        : UUID(),
            owner     : owner,
            serviceID : "service",
            scope     : ServiceScope(featureID: "main", operation: "read"),
            expiresAt : Date(timeIntervalSince1970: 2_000_000_000),
            generation: generation,
            cost      : AddonResourceRequest(
                profile              : .eventDriven,
                requestedMemoryMiB   : 0,
                maximumConcurrentWork: 1,
                background           : .none
            )
        )
    }

    func invocation() throws -> ServiceInvocation {
        try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : "service",
            operation    : "read",
            payload      : Data([1]),
            deadline     : Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    func response() throws -> ServiceResponse {
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : "service",
            operation    : "read",
            payload      : Data([9])
        )
    }

    func bindServiceEvents(_ receiver: @escaping @Sendable (Data) async throws -> Void) throws {
        try lock.withLock {
            guard self.receiver == nil else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "Already bound"
                )
            }

            self.receiver = receiver
        }
    }

    func emit(_ event: ServiceEvent) async throws {
        let receiver = lock.withLock { self.receiver }
        try await receiver?(ServiceSubscriptionFrameCodec.encode(event, profile: .v1_4))
    }

    func exchange(
        _ frame : Data,
        kind    : AddonServiceMessageKind,
        sequence: UInt64
    ) async throws -> AddonServiceMessageExchangeResult {
        lock.withLock { sequenceValues.append(sequence) }
        if let gate { await gate.pause() }
        if rejectBeforeHandoff { return .rejectedBeforeHandoff }
        if let earlyEvent { try await emit(earlyEvent) }
        if driftAfterExchange { lock.withLock { currentGeneration = ConnectionGeneration() } }
        if damage { return .response(Data("{}".utf8)) }

        switch kind {
            case .invocation:
                let request = try ServiceFrameCodec.decodeInvocationRequest(frame, profile: .v1_3)

                return .response(try ServiceFrameCodec.encode(
                    ServiceInvocationReply(
                        requestID : request.invocation.requestID,
                        contractID: request.invocation.contractID,
                        operation : request.invocation.operation,
                        result    : .completed(response())
                    ),
                    profile: .v1_3
                ))

            case .control:
                let request = try ServiceSubscriptionFrameCodec.decodeControlRequest(frame, profile: .v1_4)
                let value   = result ?? (request.kind == .subscribe ? .subscribed(alias) : .acknowledged)

                return .response(try ServiceSubscriptionFrameCodec.encode(
                    ServiceControlReply(
                        requestID: request.requestID,
                        kind     : request.kind,
                        phase    : .terminal,
                        result   : value
                    ),
                    profile: .v1_4
                ))
        }
    }

    func close() async {
        lock.withLock { closes += 1 }
        await closing.arrive()
        if let gate { await gate.pause() }
    }
}
