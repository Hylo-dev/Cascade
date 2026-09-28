//
//  AddonExecution.swift
//  Cascade
//

import Foundation

/// AddonExecution is a validated value in the version 1 addon protocol.
public struct AddonExecution: Codable, Equatable, Sendable {
    public let owner: Owner
    public let activation: Activation
    public let entryPoint: String

    public init(
        owner: Owner,
        activation: Activation,
        entryPoint: String
    ) throws {
        self.owner = owner
        self.activation = activation
        self.entryPoint = entryPoint
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(Owner.self, forKey: .owner)
        activation = try container.decode(Activation.self, forKey: .activation)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(ContractValidation.identifier(entryPoint), "Invalid entry point")
    }
    public enum Owner: String, Codable, Sendable { case cascade }
    public enum Activation: String, Codable, Sendable { case onDemand }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case owner
        case activation
        case entryPoint
    }
}
