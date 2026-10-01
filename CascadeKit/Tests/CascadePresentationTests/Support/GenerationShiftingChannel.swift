//
//  GenerationShiftingChannel.swift
//  CascadeKit
//

@testable import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing

/// GenerationShiftingChannel is a bounded canned channel that flips its physical generation
/// after the first exchange. It proves the SDK detects a stale physical generation at the very
/// next boundary and never retries a possibly completed mutation.
final class GenerationShiftingChannel: AddonAssetMessageChannel, @unchecked Sendable {

    let profile: AssetTransferFrameProfile? = .v1

    private let lock              = NSLock()
    private var currentGeneration = ConnectionGeneration()
    private var transferID       : UUID?
    private var exchanges         = 0
    private var closes            = 0

    nonisolated var generation: ConnectionGeneration { lock.withLock { currentGeneration } }

    var exchangeCount: Int { lock.withLock { exchanges } }
    var closeCount   : Int { lock.withLock { closes } }

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> Data {
        let request = try AssetTransferFrameCodec.decodeRequest(
            frame,
            profile: .v1
        )

        let response: AssetTransferResponse
        switch request.operation {
            case .begin:
                let id = UUID()
                lock.withLock { transferID = id }
                response = try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .begin,
                    result    : .begun,
                    transferID: id
                )

            case .chunk:
                let id = try #require(lock.withLock { transferID })
                response = try AssetTransferResponse(
                    requestID : request.requestID,
                    operation : .chunk,
                    result    : .acknowledged,
                    transferID: id,
                    nextOffset: try #require(request.offset) + (try #require(request.bytes).count)
                )

            default:
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "GenerationShiftingChannel stops after the first exchange."
                )
        }

        let encoded = try AssetTransferFrameCodec.encode(
            response,
            profile: .v1
        )
        lock.withLock {
            exchanges += 1
            // The physical connection was replaced between the two frames.
            currentGeneration = ConnectionGeneration()
        }

        return encoded
    }

    func close() async {
        lock.withLock { closes += 1 }
    }
}
