//
//  StorageRequest.swift
//  CascadeKit
//

import Foundation

/// StorageRequest carries one byte-addressed key and, for writes, a bounded value.
/// Use StorageFrameCodec for untrusted bytes: direct Codable does not check the
/// frame size or negotiated profile. The authenticated transport owns admission.
public struct StorageRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID    : UUID
    public let operation    : StorageOperation
    public let key          : String
    public let value        : Data?

    public init(
        schemaVersion: Int = 1,
        requestID    : UUID,
        operation    : StorageOperation,
        key          : String,
        value        : Data? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.requestID     = requestID
        self.operation     = operation
        self.key           = key
        self.value         = value
        try validate()
    }

    /// StorageRequest rejects illegal field shapes before decoding the key or value.
    /// Foundation keyed containers supply semantic fields, not lexical duplicate-key detection.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported storage request schema"
        )
        let operationName = try container.decode(
            String.self,
            forKey: .operation
        )
        guard let operation = StorageOperation(rawValue: operationName) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Unknown storage operation"
            )
        }
        self.operation = operation
        let fields = try decoder.container(keyedBy: WireKey.self)
        let expected: Set<String> =
            operation == .write
            ? ["schemaVersion", "requestID", "operation", "key", "value"]
            : ["schemaVersion", "requestID", "operation", "key"]
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == expected,
            "Storage request requires exactly its operation fields"
        )
        requestID = try container.decode(
            UUID.self,
            forKey: .requestID
        )
        key = try container.decode(
            String.self,
            forKey: .key
        )
        value =
            operation == .write
            ? try container.decode(
                Data.self,
                forKey: .value
            ) : nil
        try validate()
    }

    /// encode emits only the operation's exact field set; absent and empty remain distinct.
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
            key,
            forKey: .key
        )
        if let value {
            try container.encode(
                value,
                forKey: .value
            )
        }
    }

    /// validate preserves the existing key and value limits without normalizing keys.
    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported storage request schema"
        )
        try ContractValidation.require(
            !key.isEmpty && key.utf8.count <= StorageFrameCodec.maximumKeyBytes && !key.utf8.contains(0),
            "Invalid storage key"
        )
        try ContractValidation.require(
            (operation == .write) == (value != nil),
            "Storage value is required only for writes"
        )
        if let value {
            try ContractValidation.require(
                value.count <= StorageFrameCodec.maximumValueBytes,
                "Storage value exceeds 64 KiB"
            )
        }
    }

    /// == compares key bytes because Swift String equality treats canonically equivalent
    /// Unicode spellings as equal, while keyed storage deliberately addresses them separately.
    public static func == (
        left : Self,
        right: Self
    ) -> Bool {
        left.schemaVersion == right.schemaVersion
            && left.requestID == right.requestID
            && left.operation == right.operation
            && left.key.utf8.elementsEqual(right.key.utf8)
            && left.value == right.value
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, requestID, operation, key, value
    }
}
