//
//  ServiceResponse.swift
//  Cascade
//

import Foundation

/// ServiceResponse is a validated value in the version 1 addon protocol.
public struct ServiceResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let contractID: String
    public let operation: String
    public let payload: Data

    public init(
        schemaVersion: Int,
        contractID: String,
        operation: String,
        payload: Data
    ) throws {
        self.schemaVersion = schemaVersion
        self.contractID = contractID
        self.operation = operation
        self.payload = payload
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
        contractID = try container.decode(String.self, forKey: .contractID)
        operation = try container.decode(String.self, forKey: .operation)
        payload = try container.decode(Data.self, forKey: .payload)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1 && ContractValidation.identifier(contractID) && ContractValidation.identifier(operation),
            "Invalid service response"
        )
        try ContractValidation.require(payload.count <= 65_536, "Service payload exceeds 64 KiB")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case contractID
        case operation
        case payload
    }
}
