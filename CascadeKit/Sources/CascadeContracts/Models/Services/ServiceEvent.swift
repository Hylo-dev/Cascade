//
//  ServiceEvent.swift
//  CascadeKit
//

import Foundation

/// ServiceEvent binds a validated service payload to its subscription and connection grant.
/// Authentication, revocation and matching the current generation remain broker responsibilities.
public struct ServiceEvent: Codable, Equatable, Sendable {

    public let schemaVersion : Int
    public let subscriptionID: UUID
    public let token         : Grant
    public let response      : ServiceResponse

    public init(
        subscriptionID: UUID,
        token         : Grant,
        response      : ServiceResponse
    ) throws {
        schemaVersion       = 1
        self.subscriptionID = subscriptionID
        self.token          = token
        self.response       = response

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported service event schema")
        try token.validate()
        try response.validate()
        try ContractValidation.require(
            token.serviceID == response.contractID && token.scope.operation == response.operation,
            "Service event grant mismatch"
        )
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == [
                "schemaVersion", "subscriptionID", "token", "response",
            ],
            "Unknown service event fields"
        )

        let values     = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion  = try values.decode(Int.self, forKey: .schemaVersion)
        subscriptionID = try values.decode(UUID.self, forKey: .subscriptionID)
        token          = try values.decode(Grant.self, forKey: .token)
        response       = try values.decode(ServiceResponse.self, forKey: .response)

        try validate()
    }

    private enum CodingKeys: String, CodingKey {

        case schemaVersion, subscriptionID, token, response
    }
}
