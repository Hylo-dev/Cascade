//
//  Grant.swift
//  CascadeKit
//

import Foundation

/// Grant is a validated value in the version 1 addon protocol.
public struct Grant: Codable, Equatable, Sendable {

    public let id        : UUID
    public let owner     : AddonID
    public let serviceID : String
    public let scope     : ServiceScope
    public let expiresAt : Date
    public let generation: ConnectionGeneration
    public let cost      : AddonResourceRequest

    public init(
        id        : UUID,
        owner     : AddonID,
        serviceID : String,
        scope     : ServiceScope,
        expiresAt : Date,
        generation: ConnectionGeneration,
        cost      : AddonResourceRequest
    ) throws {
        self.id         = id
        self.owner      = owner
        self.serviceID  = serviceID
        self.scope      = scope
        self.expiresAt  = expiresAt
        self.generation = generation
        self.cost       = cost

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id            = try container.decode(UUID.self, forKey: .id)
        owner         = try container.decode(AddonID.self, forKey: .owner)
        serviceID     = try container.decode(String.self, forKey: .serviceID)
        scope         = try container.decode(ServiceScope.self, forKey: .scope)
        expiresAt     = try container.decode(Date.self, forKey: .expiresAt)
        generation    = try container.decode(ConnectionGeneration.self, forKey: .generation)
        cost          = try container.decode(AddonResourceRequest.self, forKey: .cost)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(serviceID),
            "Invalid granted service ID"
        )
        try ContractValidation.finite(expiresAt)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case owner
        case serviceID
        case scope
        case expiresAt
        case generation
        case cost
    }
}
