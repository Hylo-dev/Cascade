//
//  SDKInvocationChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

final class SDKInvocationChannel: AddonServiceInvocationMessageChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var g = ConnectionGeneration()
    private var p: ServiceInvocationFrameProfile? = .v1_3
    private var closes = 0
    private var sent: [UInt64] = []
    var generation: ConnectionGeneration { lock.withLock { g } }
    var profile: ServiceInvocationFrameProfile? { lock.withLock { p } }
    var sequences: [UInt64] { lock.withLock { sent } }
    var closeCount: Int { lock.withLock { closes } }
    // These configurations are changed only while no operation accesses them, or at a gate.
    var result: ServiceInvocationResult = .completed(try! sdkResponse())
    var damage: SDKReplyDamage?
    var transportThrows = false, rejectRequest = false
    var exchangeGate: SDKInvocationGate?, closeGate: SDKInvocationGate?
    func replaceGeneration() { lock.withLock { g = ConnectionGeneration() } }
    func withdrawProfile() { lock.withLock { p = nil } }
    func exchange(_ frame: Data, sequence: UInt64) async throws -> AddonServiceInvocationMessageExchangeResult {
        lock.withLock { sent.append(sequence) }
        let request = try ServiceFrameCodec.decodeInvocationRequest(frame, profile: .v1_3)
        await exchangeGate?.pause()
        if transportThrows { throw AddonFailure(code: .dependencyUnavailable, reason: "transport fault") }
        if rejectRequest { return .rejectedBeforeHandoff }
        if damage == .malformed { return .response(Data([123])) }
        let nested: ServiceInvocationResult
        if damage == .nestedContract || damage == .nestedOperation {
            nested = .completed(try ServiceResponse(schemaVersion: 1, contractID: damage == .nestedContract ? "wrong" : "com.example.service", operation: damage == .nestedOperation ? "wrong" : "read", payload: Data()))
        } else { nested = result }
        let reply = try ServiceInvocationReply(requestID: damage == .outerID ? UUID() : request.invocation.requestID,
            contractID: damage == .outerContract ? "wrong" : request.invocation.contractID,
            operation: damage == .outerOperation ? "wrong" : request.invocation.operation, result: nested)
        return .response(try ServiceFrameCodec.encode(reply, profile: .v1_3))
    }
    func close() async { lock.withLock { closes += 1 }; await closeGate?.pause() }
}
