//
//  StorageRuntimeByteBridge.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// StorageRuntimeByteBridge runs one physical exchange task and one shared close task. The SDK
/// owns the enclosing memory scope.
final class StorageRuntimeByteBridge: AddonStorageMessageChannel, @unchecked Sendable {

    enum HoldPoint {

        case beforeReceive
        case afterHandoff
    }

    let generation  : ConnectionGeneration
    let profile     : StorageFrameProfile?
    let gate         = StorageBridgeGate()
    let closeEntered = StorageBridgeGate()

    private let lock       = NSLock()
    private let runtime   : AddonRuntime
    private let adapter   : StorageMessageAdapter
    private let connection: RuntimeConnection

    private var holdPoint   : HoldPoint?
    private var inFlight    : Task<AddonStorageMessageExchangeResult, any Error>?
    private var closeTask   : Task<Void, Never>?
    private var revoked      = false
    private var lastSequence: UInt64 = 0
    private var result      : AddonRuntime.RuntimeStorageRequestResult?
    private var exchanges    = 0
    private var closes       = 0
    private var drained      = false
    private var fault       : Bool?

    var lastResult: AddonRuntime.RuntimeStorageRequestResult? { lock.withLock { result } }

    var exchangeCount: Int { lock.withLock { exchanges } }

    var closeCount: Int { lock.withLock { closes } }

    var didDrain: Bool { lock.withLock { drained } }

    init(
        runtime   : AddonRuntime,
        adapter   : StorageMessageAdapter,
        connection: RuntimeConnection
    ) {
        self.runtime    = runtime
        self.adapter    = adapter
        self.connection = connection
        generation      = connection.publicationConnection.generation
        profile         = connection.publicationConnection.negotiatedProtocol.storageFrameProfile
    }

    func hold(_ point: HoldPoint) async { lock.withLock { holdPoint = point } }

    func armFault(wrongNonce: Bool) { lock.withLock { fault = wrongNonce } }

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> AddonStorageMessageExchangeResult {
        let task: Task<AddonStorageMessageExchangeResult, any Error> = try lock.withLock {
            guard !revoked else { throw AddonFailure(code: .sessionRevoked, reason: "Revoked bridge") }
            guard inFlight == nil else { throw AddonFailure(code: .resourceDenied, reason: "Occupied bridge") }
            guard sequence > lastSequence, !frame.isEmpty, frame.count <= 196_608 else {
                throw AddonFailure(code: .invalidPayload, reason: "Invalid physical frame")
            }

            lastSequence = sequence
            exchanges += 1

            let created = Task { try await self.perform(frame, sequence: sequence) }
            inFlight = created
            return created
        }

        do {
            let value = try await task.value
            lock.withLock { inFlight = nil }
            return value
        } catch {
            lock.withLock { inFlight = nil }
            throw error
        }
    }

    private func perform(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> AddonStorageMessageExchangeResult {
        let request = try StorageFrameCodec.decodeRequest(frame, profile: profile)
        guard let handle = adapter.stage(
            frame,
            sequence   : sequence,
            incarnation: connection.incarnation
        ) else {
            return .rejectedBeforeHandoff
        }

        defer { adapter.rejectStorageIngress(handle, incarnation: connection.incarnation) }
        let point = lock.withLock { () -> HoldPoint? in
            defer { holdPoint = nil }
            return holdPoint
        }
        if point == .beforeReceive {
            await gate.hold()
            try checkRevoked()
        }

        let result = await runtime.receiveStorageRequest(handle, connection: connection)
        lock.withLock { self.result = result }
        guard case .completed(_, .handedOff) = result else {
            // Refused reply delivery is NOT a request-side non-exposure observation.
            throw AddonFailure(code: .dependencyUnavailable, reason: "No deliverable host response")
        }

        guard let delivery = adapter.reply else {
            throw AddonFailure(code: .dependencyUnavailable, reason: "Missing host response")
        }

        var consumed = false
        defer { if !consumed { adapter.discardTransportReply(incarnation: connection.incarnation) } }
        if point == .afterHandoff {
            await gate.hold()
            try checkRevoked()
        }

        let fault = lock.withLock { () -> Bool? in
            defer { self.fault = nil }
            return self.fault
        }
        if fault == false {
            lock.withLock { revoked = true }
            throw AddonFailure(code: .dependencyUnavailable, reason: "Physical fault after host handoff")
        }

        let original = delivery.receipt
        let receipt  = fault == true
            ? RuntimeStorageReceipt(
                token          : UUID(),
                incarnation    : original.incarnation,
                connectionToken: original.connectionToken,
                sequence       : original.sequence,
                requestID      : original.requestID,
                operation      : original.operation
            )
            : original
        guard receipt.incarnation == connection.incarnation,
              receipt.connectionToken == connection.token,
              receipt.sequence == sequence,
              receipt.requestID == request.requestID,
              receipt.operation == request.operation,
              delivery.payload.count <= 196_608,
              await runtime.receiveStorageReceipt(receipt, connection: connection)
        else {
            lock.withLock { revoked = true }
            throw AddonFailure(code: .sessionRevoked, reason: "Exact host receipt refused")
        }

        consumed = true
        return .response(delivery.payload)
    }

    private func checkRevoked() throws {
        if lock.withLock({ revoked }) {
            throw AddonFailure(code: .sessionRevoked, reason: "Closed physical exchange")
        }
    }

    func close() async {
        let task = lock.withLock { () -> Task<Void, Never> in
            if let closeTask { return closeTask }

            revoked = true
            closes += 1

            let physical = inFlight
            let created  = Task {
                await self.runtime.closeConnection(self.connection)
                await self.closeEntered.report()
                await self.gate.release()
                if let physical { _ = try? await physical.value }
                self.lock.withLock { self.drained = physical != nil }
            }
            closeTask = created
            return created
        }

        await task.value
    }
}
