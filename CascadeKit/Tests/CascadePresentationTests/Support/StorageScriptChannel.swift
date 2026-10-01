//
//  StorageScriptChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

/// StorageScriptChannel is the scripted dependency that supplies bytes; assertions exercise
/// client ordering and validation.
actor StorageScriptChannel: AddonStorageMessageChannel {

    enum Fault: Equatable, Sendable {

        case reject
        case transport
        case malformed
        case oversized
        case wrongID
        case wrongOperation
        case host(AddonFailure.Code)
    }

    struct Record: Sendable {

        let request     : StorageRequest
        let sequence    : UInt64
        let encodedBytes: Int
    }

    nonisolated let generation = ConnectionGeneration()
    nonisolated let profile   : StorageFrameProfile?

    private var fault           : Fault?
    private var values          : [Data: Data] = [:]
    private let exchangeGate    : StorageTestGate?
    private let closeGate       : StorageTestGate?
    private let exchangeFinished = StorageTestGate()
    private var running          = false
    private var closed           = false

    private(set) var records   : [Record] = []
    private(set) var closeCount = 0

    init(
        profile     : StorageFrameProfile? = .v1_1,
        fault       : Fault? = nil,
        exchangeGate: StorageTestGate? = nil,
        closeGate   : StorageTestGate? = nil
    ) {
        self.profile      = profile
        self.fault        = fault
        self.exchangeGate = exchangeGate
        self.closeGate    = closeGate
    }

    func arm(_ fault: Fault) { self.fault = fault }

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> AddonStorageMessageExchangeResult {
        let request = try StorageFrameCodec.decodeRequest(frame, profile: profile)
        records.append(Record(
            request     : request,
            sequence    : sequence,
            encodedBytes: frame.count
        ))

        let fault = self.fault
        self.fault = nil
        running    = true
        await exchangeGate?.hold()
        running = false
        await exchangeFinished.release()

        if closed || fault == .transport { throw CancellationError() }
        if fault == .reject { return .rejectedBeforeHandoff }
        if fault == .malformed { return .response(Data("{".utf8)) }
        if fault == .oversized { return .response(Data(repeating: 32, count: 196_609)) }

        let response: StorageResponse
        if case .host(let code) = fault {
            response = try StorageResponse(
                requestID    : request.requestID,
                operation    : request.operation,
                result       : .failure,
                failureCode  : code,
                failureReason: "Host refusal"
            )
        } else {
            let key    = Data(request.key.utf8)
            let result: StorageResultKind
            var value : Data?
            switch request.operation {
                case .read:
                    value  = values[key]
                    result = value == nil ? .missing : .value

                case .write:
                    values[key] = request.value
                    result = .acknowledged

                case .remove:
                    values.removeValue(forKey: key)
                    result = .acknowledged
            }

            let operation: StorageOperation = fault == .wrongOperation
                ? (request.operation == .read ? .write : .read) : request.operation
            response = try StorageResponse(
                requestID: fault == .wrongID ? UUID() : request.requestID,
                operation: operation,
                result   : fault == .wrongOperation ? (operation == .read ? .missing : .acknowledged) : result,
                value    : fault == .wrongOperation ? nil : value
            )
        }

        return .response(try StorageFrameCodec.encode(response, profile: profile))
    }

    func close() async {
        if closed { return }

        closed = true
        closeCount += 1
        await exchangeGate?.release()
        if running { await exchangeFinished.hold() }
        await closeGate?.hold()
    }
}
