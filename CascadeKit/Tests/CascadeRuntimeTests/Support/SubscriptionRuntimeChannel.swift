//
//  SubscriptionRuntimeChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// SubscriptionRuntimeChannel carries actual byte legs and exact receipts, with a
/// deterministic provider peer. It completes real admitted ServiceWork; no
/// AddonServiceClient method is stubbed.
final class SubscriptionRuntimeChannel: AddonServiceMessageChannel, @unchecked Sendable {
    let host: InvocationMessageHost
    let connection: RuntimeConnection
    private let lock = NSLock()
    private var receiver: (@Sendable (Data) async throws -> Void)?
    private var values: [UInt64] = []
    private var providerSequence: UInt64 = 1
    var sequences: [UInt64] { lock.withLock { values } }
    var generation: ConnectionGeneration { connection.publicationConnection.generation }
    var invocationProfile: ServiceInvocationFrameProfile? { connection.publicationConnection.negotiatedProtocol.serviceInvocationFrameProfile }
    var subscriptionProfile: ServiceSubscriptionFrameProfile? { connection.publicationConnection.negotiatedProtocol.serviceSubscriptionFrameProfile }
    init(host: InvocationMessageHost, connection: RuntimeConnection, providerSequence: UInt64) {
        self.host = host; self.connection = connection; self.providerSequence = providerSequence
    }
    func update(bytes: Int) async throws -> RuntimeServiceSourceOutputResult {
        let sequence = lock.withLock { providerSequence += 1; return providerSequence }
        return try await host.update(bytes: bytes, sequence: sequence, escaped: true)
    }
    func bindServiceEvents(_ receiver: @escaping @Sendable (Data) async throws -> Void) throws {
        try lock.withLock {
            guard self.receiver == nil else { throw AddonFailure(code: .resourceDenied, reason: "Receiver already bound") }
            self.receiver = receiver
        }
    }
    func consumeEvent() async throws {
        guard case .serviceEvent(let delivery) = host.adapter.payload(connection.incarnation) else { throw AddonFailure(code: .invalidPayload, reason: "No event") }
        // Exercise fully escaped event bytes (encoder output already slash-escapes).
        let bytes = delivery.payload.withUnsafeBytes { Data($0) }
        guard await host.runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: connection) else {
            throw AddonFailure(code: .permissionDenied, reason: "Event receipt refused")
        }
        let callback = lock.withLock { receiver }
        try await callback?(bytes)
    }
    func exchange(_ frame: Data, kind: AddonServiceMessageKind, sequence: UInt64) async throws -> AddonServiceMessageExchangeResult {
        lock.withLock { values.append(sequence) }
        let wireKind: RuntimeServiceIngressKind = kind == .invocation ? .invocation : .control
        guard let ingress = host.adapter.stage(frame, connection: connection, sequence: sequence, kind: wireKind) else { return .rejectedBeforeHandoff }
        let admitted: RuntimeServiceInvocationExchange.Admission
        if kind == .control { admitted = await host.runtime.receiveServiceControl(ingress, connection: connection) }
        else { admitted = await host.runtime.receiveServiceRequest(ingress, connection: connection) }
        guard case .admitted = admitted else { throw AddonFailure(code: .outcomeUnknown, reason: "Host processing refused") }
        if kind == .invocation {
            let delivery = try #require(host.providerDelivery)
            let request = try ServiceFrameCodec.decodeInvocationRequest(frame, profile: .v1_3)
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.provider))
            let outputSequence = lock.withLock { providerSequence += 1; return providerSequence }
            try await host.complete(request.invocation.requestID, sequence: outputSequence)
            guard case .serviceReply(let reply) = host.adapter.payload(connection.incarnation) else { throw AddonFailure(code: .outcomeUnknown, reason: "No invocation reply") }
            let bytes = reply.payload.withUnsafeBytes { Data($0) }
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: connection))
            return .response(bytes)
        }
        let request = try ServiceSubscriptionFrameCodec.decodeControlRequest(frame, profile: .v1_4)
        for _ in 0..<2 {
            guard case .serviceControl(let delivery) = host.adapter.payload(connection.incarnation) else { throw AddonFailure(code: .outcomeUnknown, reason: "No control reply") }
            let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(delivery.payload, profile: .v1_4)
            try reply.validate(matching: request)
            let bytes = delivery.payload.withUnsafeBytes { Data($0) }
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: connection))
            if reply.phase == .terminal {
                if case .serviceEvent = host.adapter.payload(connection.incarnation) { try await consumeEvent() }
                return .response(bytes)
            }
        }
        throw AddonFailure(code: .outcomeUnknown, reason: "Acquisition did not finish")
    }
    func close() async { await host.runtime.closeConnection(connection) }
}
