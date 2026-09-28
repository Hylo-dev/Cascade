//
//  AssetTransferResponse.swift
//  Cascade
//

import Foundation

/// AssetTransferResultKind distinguishes host acceptance, progress and protected import.
/// `shared` reports a fresh canonical alias over an existing raster without new transfer state.
public enum AssetTransferResultKind: String, Codable, Sendable {
    case begun, acknowledged, imported, shared, failure
}
/// AssetTransferResponse is a closed semantic frame; transport admission and authority remain host-owned.
public struct AssetTransferResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID    : UUID
    public let operation    : AssetTransferOperation
    public let result       : AssetTransferResultKind
    public let transferID   : UUID?
    public let nextOffset   : Int?
    public let assetHandle  : AssetHandle?
    public let failureCode  : AddonFailure.Code?
    public let failureReason: String?

    public init(
        schemaVersion: Int = 1,
        requestID    : UUID,
        operation    : AssetTransferOperation,
        result       : AssetTransferResultKind,
        transferID   : UUID? = nil,
        nextOffset   : Int? = nil,
        assetHandle  : AssetHandle? = nil,
        failureCode  : AddonFailure.Code? = nil,
        failureReason: String? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.requestID     = requestID
        self.operation     = operation
        self.result        = result
        self.transferID    = transferID
        self.nextOffset    = nextOffset
        self.assetHandle   = assetHandle
        self.failureCode   = failureCode
        self.failureReason = failureReason
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported asset transfer schema"
        )
        let operationName = try container.decode(
            String.self,
            forKey: .operation
        )
        guard let operation = AssetTransferOperation(rawValue: operationName) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Unknown asset operation"
            )
        }
        self.operation = operation
        let resultName = try container.decode(
            String.self,
            forKey: .result
        )
        guard let result = AssetTransferResultKind(rawValue: resultName) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Unknown asset result"
            )
        }
        self.result = result
        let fields = try decoder.container(keyedBy: WireKey.self)
        var expected: Set<String> = ["schemaVersion", "requestID", "operation", "result"]
        switch result {
        case .begun: expected.insert("transferID")
        case .acknowledged:
            switch operation {
            case .chunk: expected.formUnion(["transferID", "nextOffset"])
            case .abort: expected.insert("transferID")
            case .release: break
            default: expected.insert("transferID")
            }
        case .imported: expected.formUnion(["transferID", "assetHandle"])
        case .shared: expected.insert("assetHandle")
        case .failure: expected.formUnion(["failureCode", "failureReason"])
        }
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == expected,
            "Asset transfer requires exactly its operation/result fields"
        )
        requestID = try container.decode(
            UUID.self,
            forKey: .requestID
        )
        transferID = expected.contains("transferID")
            ? try container.decode(
                UUID.self,
                forKey: .transferID
            ) : nil
        nextOffset = expected.contains("nextOffset")
            ? try container.decode(
                Int.self,
                forKey: .nextOffset
            ) : nil
        assetHandle = expected.contains("assetHandle")
            ? try container.decode(
                AssetHandle.self,
                forKey: .assetHandle
            ) : nil
        if result == .failure {
            let codeName = try container.decode(
                String.self,
                forKey: .failureCode
            )
            guard let code = AddonFailure.Code(rawValue: codeName) else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Unknown asset failure code"
                )
            }
            failureCode = code
        } else {
            failureCode = nil
        }
        failureReason = expected.contains("failureReason")
            ? try container.decode(
                String.self,
                forKey: .failureReason
            ) : nil
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            schemaVersion,
            forKey: .schemaVersion
        )
        try container.encode(
            requestID,
            forKey: .requestID
        )
        try container.encode(
            operation,
            forKey: .operation
        )
        try container.encode(
            result,
            forKey: .result
        )
        try container.encodeIfPresent(
            transferID,
            forKey: .transferID
        )
        try container.encodeIfPresent(
            nextOffset,
            forKey: .nextOffset
        )
        try container.encodeIfPresent(
            assetHandle,
            forKey: .assetHandle
        )
        try container.encodeIfPresent(
            failureCode,
            forKey: .failureCode
        )
        try container.encodeIfPresent(
            failureReason,
            forKey: .failureReason
        )
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported asset transfer schema"
        )
        switch result {
        case .begun:
            try ContractValidation.require(
                operation == .begin && transferID != nil && nextOffset == nil && assetHandle == nil,
                "Invalid begin result"
            )
        case .acknowledged:
            switch operation {
            case .chunk:
                try ContractValidation.require(
                    transferID != nil && nextOffset != nil && assetHandle == nil,
                    "Invalid chunk acknowledgement"
                )
            case .abort:
                try ContractValidation.require(
                    transferID != nil && nextOffset == nil && assetHandle == nil,
                    "Invalid abort acknowledgement"
                )
            case .release:
                try ContractValidation.require(
                    transferID == nil && nextOffset == nil && assetHandle == nil,
                    "Invalid release acknowledgement"
                )
            case .begin, .finish, .share:
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Acknowledgement is not valid for this operation"
                )
            }
        case .imported:
            try ContractValidation.require(
                operation == .finish && transferID != nil && nextOffset == nil && assetHandle != nil,
                "Invalid imported result"
            )
        case .shared:
            try ContractValidation.require(
                operation == .share && transferID == nil && nextOffset == nil && assetHandle != nil,
                "Invalid shared result"
            )
        case .failure:
            try ContractValidation.require(
                transferID == nil && nextOffset == nil && assetHandle == nil,
                "Invalid failure fields"
            )
        }
        try ContractValidation.require(
            (result == .failure) == (failureCode != nil) && (result == .failure) == (failureReason != nil),
            "Invalid failure shape"
        )
        if let nextOffset {
            try ContractValidation.require(
                (1...1_048_576).contains(nextOffset),
                "Invalid chunk acknowledgement"
            )
        }
        if let failureReason {
            try ContractValidation.require(
                !failureReason.isEmpty && failureReason.utf8.count <= 4_096,
                "Invalid asset failure reason"
            )
        }
        try assetHandle?.validate()
    }

    /// validate checks exact receipt correlation; UUIDs alone grant no authority or replay support.
    public func validate(matching request: AssetTransferRequest) throws {
        try validate()
        try request.validate()
        try ContractValidation.require(
            requestID == request.requestID && operation == request.operation,
            "Asset response does not match its request"
        )
        if result != .failure, operation != .begin {
            try ContractValidation.require(
                transferID == request.transferID,
                "Asset transfer token mismatch"
            )
        }
        if result == .acknowledged, operation == .chunk, let offset = request.offset, let bytes = request.bytes {
            try ContractValidation.require(
                nextOffset == offset + bytes.count,
                "Asset receipt progress mismatch"
            )
        }
        if result == .shared, let source = request.sourceHandle, let handle = assetHandle {
            try ContractValidation.require(
                handle.owner == source.owner && handle.publicationID == request.publicationID,
                "Shared alias does not match its source owner or target publication"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, requestID, operation, result, transferID, nextOffset, assetHandle, failureCode, failureReason
    }
}
