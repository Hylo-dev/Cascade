//
//  ServiceInvocationRequest.swift
//  CascadeKit
//

import Foundation

/// ServiceInvocationRequest is consumer syntax carrying a grant reference, never
/// provider or session authority.
public struct ServiceInvocationRequest: Codable, Equatable, Sendable {

    public let schemaVersion: Int
    public let grantID      : UUID
    public let invocation   : ServiceInvocation

    public init(
        schemaVersion: Int = 1,
        grantID      : UUID,
        invocation   : ServiceInvocation
    ) throws {
        self.schemaVersion = schemaVersion
        self.grantID       = grantID
        self.invocation    = invocation

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try ContractValidation.require(
            try values.decode(String.self, forKey: .kind) == "invoke",
            "Unknown service request kind"
        )

        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == ["schemaVersion", "kind", "grantID", "invocation"],
            "Invalid service request fields"
        )

        try self.init(
            schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
            grantID      : values.decode(UUID.self, forKey: .grantID),
            invocation   : values.decode(ServiceInvocation.self, forKey: .invocation)
        )
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported service request schema")
        try invocation.validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()

        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode("invoke", forKey: .kind)
        try values.encode(grantID, forKey: .grantID)
        try values.encode(invocation, forKey: .invocation)
    }

    private enum CodingKeys: String, CodingKey {

        case schemaVersion, kind, grantID, invocation
    }
}
