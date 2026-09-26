//
//  ServiceInvocation.swift
//  Cascade
//

import Foundation

/// ServiceInvocation is a validated value in the version 1 addon protocol.
public struct ServiceInvocation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let contractID: String
    public let operation: String
    public let payload: Data
    public let deadline: Date

    public init(
        schemaVersion: Int,
        requestID: UUID,
        contractID: String,
        operation: String,
        payload: Data,
        deadline: Date
    ) throws {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.contractID = contractID
        self.operation = operation
        self.payload = payload
        self.deadline = deadline
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        contractID = try container.decode(String.self, forKey: .contractID)
        operation = try container.decode(String.self, forKey: .operation)
        payload = try container.decode(Data.self, forKey: .payload)
        deadline = try container.decode(Date.self, forKey: .deadline)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1 && ContractValidation.identifier(contractID) && ContractValidation.identifier(operation),
            "Invalid service invocation"
        )
        try ContractValidation.require(payload.count <= 65_536, "Service payload exceeds 64 KiB")
        try ContractValidation.finite(deadline)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case requestID
        case contractID
        case operation
        case payload
        case deadline
    }
}
