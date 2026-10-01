//
//  AssetTransferFrameTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeContracts

@Suite
struct AssetTransferFrameTests {

    @Test
    func operationsAndResultsRoundTripAndCorrelate() throws {
        let owner       = try #require(AddonID(rawValue: "com.example.assets"))
        let publication = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let token  = UUID()
        let handle = try AssetHandle(
            assetID       : "image",
            owner         : owner,
            publicationID : publication,
            rasterRevision: 1,
            width         : 1,
            height        : 1,
            byteCount     : 4
        )
        let target = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let requests = try [
            AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: publication,
                totalBytes   : 1
            ),
            AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: token,
                offset    : 0,
                bytes     : Data([1])
            ),
            AssetTransferRequest(
                requestID : UUID(),
                operation : .finish,
                transferID: token
            ),
            AssetTransferRequest(
                requestID : UUID(),
                operation : .abort,
                transferID: token
            ),
            AssetTransferRequest(
                requestID    : UUID(),
                operation    : .share,
                publicationID: target,
                sourceHandle : handle
            ),
            AssetTransferRequest(
                requestID   : UUID(),
                operation   : .release,
                sourceHandle: handle
            )
        ]

        for request in requests {
            let encoded = try AssetTransferFrameCodec.encode(
                request,
                profile: .v1
            )
            #expect(try AssetTransferFrameCodec.decodeRequest(
                encoded,
                profile: .v1
            ) == request)

            let response: AssetTransferResponse
            switch request.operation {
                case .begin:
                    response = try AssetTransferResponse(
                        requestID : request.requestID,
                        operation : .begin,
                        result    : .begun,
                        transferID: token
                    )

                case .chunk:
                    response = try AssetTransferResponse(
                        requestID : request.requestID,
                        operation : .chunk,
                        result    : .acknowledged,
                        transferID: token,
                        nextOffset: 1
                    )

                case .finish:
                    response = try AssetTransferResponse(
                        requestID  : request.requestID,
                        operation  : .finish,
                        result     : .imported,
                        transferID : token,
                        assetHandle: handle
                    )

                case .abort:
                    response = try AssetTransferResponse(
                        requestID : request.requestID,
                        operation : .abort,
                        result    : .acknowledged,
                        transferID: token
                    )

                case .share:
                    response = try AssetTransferResponse(
                        requestID  : request.requestID,
                        operation  : .share,
                        result     : .shared,
                        assetHandle: try AssetHandle(
                            assetID       : "shared",
                            owner         : owner,
                            publicationID : target,
                            rasterRevision: 1,
                            width         : 1,
                            height        : 1,
                            byteCount     : 4
                        )
                    )

                case .release:
                    response = try AssetTransferResponse(
                        requestID: request.requestID,
                        operation: .release,
                        result   : .acknowledged
                    )
            }

            try response.validate(matching: request)
            let responseBytes = try AssetTransferFrameCodec.encode(
                response,
                profile: .v1
            )
            #expect(try AssetTransferFrameCodec.decodeResponse(
                responseBytes,
                profile: .v1
            ) == response)

            let failure = try AssetTransferResponse(
                requestID    : request.requestID,
                operation    : request.operation,
                result       : .failure,
                failureCode  : .invalidPayload,
                failureReason: "Malformed image"
            )
            try failure.validate(matching: request)
            #expect(try JSONDecoder().decode(
                AssetTransferResponse.self,
                from: JSONEncoder().encode(failure)
            ) == failure)

            let wrongID = try AssetTransferResponse(
                requestID    : UUID(),
                operation    : request.operation,
                result       : .failure,
                failureCode  : .invalidPayload,
                failureReason: "Rejected"
            )
            #expect(throws: AddonFailure.self) { try wrongID.validate(matching: request) }

            try rejectMutatedFields(
                encoded,
                type: AssetTransferRequest.self
            )
            try rejectMutatedFields(
                responseBytes,
                type: AssetTransferResponse.self
            )
        }

        let chunk = requests[1]
        for (receiptToken, nextOffset) in [(UUID(), 1), (token, 2)] {
            let response = try AssetTransferResponse(
                requestID : chunk.requestID,
                operation : .chunk,
                result    : .acknowledged,
                transferID: receiptToken,
                nextOffset: nextOffset
            )
            #expect(throws: AddonFailure.self) { try response.validate(matching: chunk) }
        }
    }

    @Test
    func numericAndByteBoundsPrecedeUnsafeArithmetic() throws {
        let owner       = try #require(AddonID(rawValue: "com.example.assets"))
        let publication = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )

        for length in [Int.min, -1, 0, 1_048_577, Int.max] {
            #expect(throws: AddonFailure.self) {
                try AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: publication,
                    totalBytes   : length
                )
            }
        }

        for length in [1, 1_048_576] {
            _ = try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: publication,
                totalBytes   : length
            )
        }

        for (offset, length) in [
            (Int.min, 1), (-1, 1), (Int.max, 1), (1_048_576, 1), (1_048_575, 2), (0, 0), (0, 65_537)
        ] {
            #expect(throws: AddonFailure.self) {
                try AssetTransferRequest(
                    requestID : UUID(),
                    operation : .chunk,
                    transferID: UUID(),
                    offset    : offset,
                    bytes     : Data(count: length)
                )
            }
        }

        for reason in ["", String(repeating: "é", count: 2_049)] {
            #expect(throws: AddonFailure.self) {
                try AssetTransferResponse(
                    requestID    : UUID(),
                    operation    : .finish,
                    result       : .failure,
                    failureCode  : .invalidPayload,
                    failureReason: reason
                )
            }
        }

        let reason  = String(repeating: "é", count: 2_048)
        let failure = try AssetTransferResponse(
            requestID    : UUID(),
            operation    : .finish,
            result       : .failure,
            failureCode  : .invalidPayload,
            failureReason: reason
        )

        #expect(try JSONDecoder().decode(
            AssetTransferResponse.self,
            from: JSONEncoder().encode(failure)
        ) == failure)
    }

    @Test
    func shareAndReleaseShapesAreClosedAndCorrelated() throws {
        let owner  = try #require(AddonID(rawValue: "com.example.assets"))
        let source = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let target = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let handle = try AssetHandle(
            assetID       : "image",
            owner         : owner,
            publicationID : source,
            rasterRevision: 1,
            width         : 1,
            height        : 1,
            byteCount     : 4
        )

        // Field sets are exact: unexpected/absent companions are rejected.
        #expect(throws: AddonFailure.self) {
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .share,
                publicationID: target,
                totalBytes   : 1,
                sourceHandle : handle
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .share,
                publicationID: target
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .release,
                publicationID: source,
                sourceHandle : handle
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferRequest(
                requestID   : UUID(),
                operation   : .release,
                bytes       : Data([1]),
                sourceHandle: handle
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: source,
                totalBytes   : 1,
                sourceHandle : handle
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferRequest(
                requestID   : UUID(),
                operation   : .finish,
                transferID  : UUID(),
                sourceHandle: handle
            )
        }

        // Shared result fields are exact and correlated with the requested target/adapter alias.
        let share = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .share,
            publicationID: target,
            sourceHandle : handle
        )
        #expect(throws: AddonFailure.self) {
            try AssetTransferResponse(
                requestID  : share.requestID,
                operation  : .share,
                result     : .shared,
                transferID : UUID(),
                assetHandle: handle
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferResponse(
                requestID  : share.requestID,
                operation  : .share,
                result     : .shared,
                nextOffset : 4,
                assetHandle: handle
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferResponse(
                requestID: share.requestID,
                operation: .share,
                result   : .shared
            )
        }

        let otherOwner       = try #require(AddonID(rawValue: "com.example.other"))
        let otherPublication = PublicationID(
            addonID   : otherOwner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let wrongOwner = try AssetHandle(
            assetID       : "image",
            owner         : otherOwner,
            publicationID : otherPublication,
            rasterRevision: 1,
            width         : 1,
            height        : 1,
            byteCount     : 4
        )
        let wrongOwnerResponse = try AssetTransferResponse(
            requestID  : share.requestID,
            operation  : .share,
            result     : .shared,
            assetHandle: wrongOwner
        )
        #expect(throws: AddonFailure.self) { try wrongOwnerResponse.validate(matching: share) }

        let wrongTargetResponse = try AssetTransferResponse(
            requestID  : share.requestID,
            operation  : .share,
            result     : .shared,
            assetHandle: try AssetHandle(
                assetID       : "image",
                owner         : owner,
                publicationID : source,
                rasterRevision: 1,
                width         : 1,
                height        : 1,
                byteCount     : 4
            )
        )
        #expect(throws: AddonFailure.self) { try wrongTargetResponse.validate(matching: share) }

        // Release acknowledgement carries no transfer token or progress.
        let release = try AssetTransferRequest(
            requestID   : UUID(),
            operation   : .release,
            sourceHandle: handle
        )
        #expect(throws: AddonFailure.self) {
            try AssetTransferResponse(
                requestID : release.requestID,
                operation : .release,
                result    : .acknowledged,
                transferID: UUID()
            )
        }
        #expect(throws: AddonFailure.self) {
            try AssetTransferResponse(
                requestID : release.requestID,
                operation : .release,
                result    : .acknowledged,
                nextOffset: 4
            )
        }
        try AssetTransferResponse(
            requestID: release.requestID,
            operation: .release,
            result   : .acknowledged
        ).validate(matching: release)

        // A shared result may not masquerade as another operation's acknowledgement.
        #expect(throws: AddonFailure.self) {
            try AssetTransferResponse(
                requestID  : release.requestID,
                operation  : .release,
                result     : .shared,
                assetHandle: handle
            )
        }

        // Worst-case nested source handle plus target publication stays far below the cap.
        let longOwner  = try #require(AddonID(rawValue: "a." + String(repeating: "a", count: 126)))
        let longSource = PublicationID(
            addonID   : longOwner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let longTarget = PublicationID(
            addonID   : longOwner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let longHandle = try AssetHandle(
            assetID       : String(repeating: "a", count: 128),
            owner         : longOwner,
            publicationID : longSource,
            rasterRevision: UInt64.max,
            width         : 1_000_000,
            height        : 1,
            byteCount     : 4_000_000
        )
        let longShare = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .share,
            publicationID: longTarget,
            sourceHandle : longHandle
        )

        let longBytes = try AssetTransferFrameCodec.encode(longShare, profile: .v1)
        #expect(longBytes.count <= 3_072)
        #expect(longBytes.count <= AssetTransferFrameCodec.maximumEncodedBytes)
        #expect(try AssetTransferFrameCodec.decodeRequest(longBytes, profile: .v1) == longShare)
        try rejectMutatedFields(longBytes, type: AssetTransferRequest.self)
    }

    @Test
    func wireAccountingAndPreparseGates() throws {
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: UUID(),
            offset    : 983_040,
            bytes     : Data(repeating: 255, count: 65_536)
        )
        let encoded = try AssetTransferFrameCodec.encode(
            chunk,
            profile: .v1
        )

        #expect(encoded.count <= 175_280)
        #expect(try AssetTransferFrameCodec.decodeRequest(
            encoded,
            profile: .v1
        ) == chunk)

        let owner       = try #require(AddonID(rawValue: "a." + String(repeating: "a", count: 253)))
        let publication = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: publication,
            totalBytes   : 1_048_576
        )
        #expect(try AssetTransferFrameCodec.encode(
            begin,
            profile: .v1
        ).count <= 883)

        let handle = try AssetHandle(
            assetID       : String(repeating: "a", count: 128),
            owner         : owner,
            publicationID : publication,
            rasterRevision: UInt64.max,
            width         : 1_000_000,
            height        : 1,
            byteCount     : 4_000_000
        )
        let imported = try AssetTransferResponse(
            requestID  : UUID(),
            operation  : .finish,
            result     : .imported,
            transferID : UUID(),
            assetHandle: handle
        )
        #expect(try AssetTransferFrameCodec.encode(
            imported,
            profile: .v1
        ).count <= 1_848)

        do {
            _ = try AssetTransferFrameCodec.decodeRequest(
                Data([255]),
                profile: nil
            )
            Issue.record("Missing profile was accepted")
        } catch let failure as AddonFailure {
            #expect(failure.code == .versionConflict)
        }

        do {
            _ = try AssetTransferFrameCodec.decodeResponse(
                Data(repeating: 255, count: 196_609),
                profile: .v1
            )
            Issue.record("Oversized poison reached parser")
        } catch let failure as AddonFailure {
            #expect(failure.code == .invalidPayload)
        }

        #expect(StorageFrameCodec.maximumValueBytes == 65_536)
    }
}

/// rejectMutatedFields exercises missing/null/unknown fields through direct Codable as well.
private func rejectMutatedFields<Value: Decodable>(
    _ encoded: Data,
    type     : Value.Type
) throws {
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    for key in object.keys {
        var missing = object
        missing.removeValue(forKey: key)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                type,
                from: JSONSerialization.data(withJSONObject: missing)
            )
        }

        var null = object
        null[key] = NSNull()
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                type,
                from: JSONSerialization.data(withJSONObject: null)
            )
        }
    }

    for (key, value) in [("owner", "forbidden"), ("schemaVersion", "unknown"), ("operation", "unknown")] {
        var unknown = object
        unknown[key] = value
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                type,
                from: JSONSerialization.data(withJSONObject: unknown)
            )
        }
    }

    var schema = object
    schema["schemaVersion"] = 2
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(
            type,
            from: JSONSerialization.data(withJSONObject: schema)
        )
    }
}
