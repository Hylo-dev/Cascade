//
//  ServiceScope.swift
//  Cascade
//

import Foundation

/// ServiceScope is a validated value in the version 1 addon protocol.
public struct ServiceScope: Codable, Equatable, Sendable {
    public let featureID: String
    public let operation: String

    public init(
        featureID: String,
        operation: String
    ) throws {
        self.featureID = featureID
        self.operation = operation
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let allKeys = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(allKeys.allKeys.map(\.stringValue)).isSubset(of: ["featureID", "operation"]),
            "Unknown service scope field"
        )
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        featureID = try container.decode(String.self, forKey: .featureID)
        operation = try container.decode(String.self, forKey: .operation)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(featureID) && ContractValidation.identifier(operation),
            "Invalid service scope"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case featureID
        case operation
    }
}
