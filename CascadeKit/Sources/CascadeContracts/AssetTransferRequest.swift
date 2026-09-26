//
//  AssetTransferRequest.swift
//  Cascade
//

import Foundation

/// AssetTransferOperation names syntax without granting publication authority.
/// `share` and `release` act on an existing canonical alias instead of a byte transfer.
public enum AssetTransferOperation: String, Codable, Sendable {
    case begin, chunk, finish, abort, share, release
}
/// AssetTransferRequest is a closed semantic frame; transport admission and authority remain host-owned.
public struct AssetTransferRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID    : UUID
    public let operation    : AssetTransferOperation
    public let publicationID: PublicationID?
    public let totalBytes   : Int?
    public let transferID   : UUID?
    public let offset       : Int?
    public let bytes        : Data?
    /// sourceHandle is the canonical host alias referenced by share/release; it is metadata only.
    public let sourceHandle : AssetHandle?

    public init(
        schemaVersion: Int = 1,
        requestID    : UUID,
        operation    : AssetTransferOperation,
        publicationID: PublicationID? = nil,
        totalBytes   : Int? = nil,
        transferID   : UUID? = nil,
        offset       : Int? = nil,
        bytes        : Data? = nil,
        sourceHandle : AssetHandle? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.requestID     = requestID
        self.operation     = operation
        self.publicationID = publicationID
        self.totalBytes    = totalBytes
        self.transferID    = transferID
        self.offset        = offset
        self.bytes         = bytes
        self.sourceHandle  = sourceHandle
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
        let fields = try decoder.container(keyedBy: WireKey.self)
        var expected: Set<String> = ["schemaVersion", "requestID", "operation"]
        switch operation {
        case .begin: expected.formUnion(["publicationID", "totalBytes"])
        case .chunk: expected.formUnion(["transferID", "offset", "bytes"])
        case .finish, .abort: expected.insert("transferID")
        case .share: expected.formUnion(["sourceHandle", "publicationID"])
        case .release: expected.insert("sourceHandle")
        }
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == expected,
            "Asset transfer requires exactly its operation/result fields"
        )
        requestID = try container.decode(
            UUID.self,
            forKey: .requestID
        )
        publicationID = expected.contains("publicationID")
            ? try container.decode(
                PublicationID.self,
                forKey: .publicationID
            ) : nil
        totalBytes = expected.contains("totalBytes")
            ? try container.decode(
                Int.self,
                forKey: .totalBytes
            ) : nil
        transferID = expected.contains("transferID")
            ? try container.decode(
                UUID.self,
                forKey: .transferID
            ) : nil
        offset = expected.contains("offset")
            ? try container.decode(
                Int.self,
                forKey: .offset
            ) : nil
        bytes = expected.contains("bytes")
            ? try container.decode(
                Data.self,
                forKey: .bytes
            ) : nil
        sourceHandle = expected.contains("sourceHandle")
            ? try container.decode(
                AssetHandle.self,
                forKey: .sourceHandle
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
        try container.encodeIfPresent(
            publicationID,
            forKey: .publicationID
        )
        try container.encodeIfPresent(
            totalBytes,
            forKey: .totalBytes
        )
        try container.encodeIfPresent(
            transferID,
            forKey: .transferID
        )
        try container.encodeIfPresent(
            offset,
            forKey: .offset
        )
        try container.encodeIfPresent(
            bytes,
            forKey: .bytes
        )
        try container.encodeIfPresent(
            sourceHandle,
            forKey: .sourceHandle
        )
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported asset transfer schema"
        )
        switch operation {
        case .begin:
            try ContractValidation.require(
                publicationID != nil && totalBytes != nil && transferID == nil && offset == nil && bytes == nil
                    && sourceHandle == nil,
                "Invalid begin fields"
            )
        case .chunk:
            try ContractValidation.require(
                publicationID == nil && totalBytes == nil && transferID != nil && offset != nil && bytes != nil
                    && sourceHandle == nil,
                "Invalid chunk fields"
            )
        case .finish, .abort:
            try ContractValidation.require(
                publicationID == nil && totalBytes == nil && transferID != nil && offset == nil && bytes == nil
                    && sourceHandle == nil,
                "Invalid completion fields"
            )
        case .share:
            try ContractValidation.require(
                publicationID != nil && sourceHandle != nil && totalBytes == nil && transferID == nil
                    && offset == nil && bytes == nil,
                "Invalid share fields"
            )
        case .release:
            try ContractValidation.require(
                sourceHandle != nil && publicationID == nil && totalBytes == nil && transferID == nil
                    && offset == nil && bytes == nil,
                "Invalid release fields"
            )
        }
        try sourceHandle?.validate()
        if let totalBytes {
            try ContractValidation.require(
                (1...1_048_576).contains(totalBytes),
                "Invalid asset length"
            )
        }
        if let offset, let bytes {
            // Subtraction follows the offset bound, so hostile Int extremes cannot overflow.
            try ContractValidation.require(
                offset >= 0 && offset < 1_048_576 && !bytes.isEmpty && bytes.count <= 65_536
                    && bytes.count <= 1_048_576 - offset,
                "Invalid asset chunk bounds"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, requestID, operation, publicationID, totalBytes, transferID, offset, bytes, sourceHandle
    }
}
