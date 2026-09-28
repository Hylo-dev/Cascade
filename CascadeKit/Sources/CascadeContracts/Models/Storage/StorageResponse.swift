//
//  StorageResponse.swift
//  CascadeKit
//

import Foundation

/// StorageResponse returns one operation's result without echoing its key or authority.
/// Use StorageFrameCodec for raw ingress bounds and the negotiated capability gate.
public struct StorageResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID    : UUID
    public let operation    : StorageOperation
    public let result       : StorageResultKind
    public let value        : Data?
    public let failureCode  : AddonFailure.Code?
    public let failureReason: String?

    public init(
        schemaVersion: Int = 1,
        requestID    : UUID,
        operation    : StorageOperation,
        result       : StorageResultKind,
        value        : Data? = nil,
        failureCode  : AddonFailure.Code? = nil,
        failureReason: String? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.requestID     = requestID
        self.operation     = operation
        self.result        = result
        self.value         = value
        self.failureCode   = failureCode
        self.failureReason = failureReason
        try validate()
    }

    /// StorageResponse checks the closed result shape before decoding variable payloads.
    /// Unknown enum strings are semantic failures; wrong JSON types remain DecodingError.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported storage response schema"
        )
        let operationName = try container.decode(
            String.self,
            forKey: .operation
        )
        let resultName = try container.decode(
            String.self,
            forKey: .result
        )
        guard let operation = StorageOperation(rawValue: operationName),
            let result = StorageResultKind(rawValue: resultName)
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Unknown storage operation or result"
            )
        }
        self.operation = operation
        self.result    = result
        var expected: Set<String> = ["schemaVersion", "requestID", "operation", "result"]
        switch result {
        case .value:
            expected.insert("value")
        case .failure:
            expected.formUnion(["failureCode", "failureReason"])
        case .missing, .acknowledged:
            break
        }
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == expected,
            "Storage response requires exactly its result fields"
        )
        requestID = try container.decode(
            UUID.self,
            forKey: .requestID
        )
        value =
            result == .value
            ? try container.decode(
                Data.self,
                forKey: .value
            ) : nil
        if result == .failure {
            let codeName = try container.decode(
                String.self,
                forKey: .failureCode
            )
            guard let code = AddonFailure.Code(rawValue: codeName) else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Unknown storage failure code"
                )
            }
            failureCode = code
            failureReason = try container.decode(
                String.self,
                forKey: .failureReason
            )
        } else {
            failureCode = nil
            failureReason = nil
        }
        try validate()
    }

    /// encode emits the result's exact field set, with no null placeholders.
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
        if let value {
            try container.encode(
                value,
                forKey: .value
            )
        }
        if let failureCode {
            try container.encode(
                failureCode,
                forKey: .failureCode
            )
        }
        if let failureReason {
            try container.encode(
                failureReason,
                forKey: .failureReason
            )
        }
    }

    /// validate enforces operation/result compatibility and rejects unbounded failure text
    /// without invoking AddonFailure's convenience initializer, which truncates its input.
    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1,
            "Unsupported storage response schema"
        )
        switch result {
        case .value:
            try ContractValidation.require(
                operation == .read && value != nil && failureCode == nil && failureReason == nil,
                "Invalid storage value result"
            )
        case .missing:
            try ContractValidation.require(
                operation == .read && value == nil && failureCode == nil && failureReason == nil,
                "Invalid missing storage result"
            )
        case .acknowledged:
            try ContractValidation.require(
                operation != .read && value == nil && failureCode == nil && failureReason == nil,
                "Invalid storage acknowledgement"
            )
        case .failure:
            try ContractValidation.require(
                value == nil && failureCode != nil && failureReason != nil,
                "Invalid storage failure result"
            )
        }
        if let value {
            try ContractValidation.require(
                value.count <= StorageFrameCodec.maximumValueBytes,
                "Storage value exceeds 64 KiB"
            )
        }
        if let failureReason {
            try ContractValidation.require(
                !failureReason.isEmpty
                    && failureReason.utf8.count <= StorageFrameCodec.maximumFailureReasonBytes,
                "Invalid storage failure reason"
            )
        }
    }

    /// validate checks correlation only. The caller must independently authenticate the
    /// connection and consume its canonical outstanding request once; this is not replay protection.
    public func validate(matching request: StorageRequest) throws {
        try validate()
        try request.validate()
        try ContractValidation.require(
            requestID == request.requestID && operation == request.operation,
            "Storage response does not match its request"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, requestID, operation, result, value, failureCode, failureReason
    }
}
