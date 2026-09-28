//
//  ServiceControlRequest.swift
//  CascadeKit
//

import Foundation

public struct ServiceControlRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let action: ServiceControlAction
    public var kind: ServiceControlKind {
        switch action {
        case .acquire: return .acquire
        case .subscribe: return .subscribe
        case .unsubscribe: return .unsubscribe
        }
    }

    public init(schemaVersion: Int = 1, requestID: UUID, action: ServiceControlAction) throws {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.action = action
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported service control schema")
        switch action {
        case .acquire(let operation):
            guard case .requestService = operation else {
                throw AddonFailure(code: .invalidPayload, reason: "Acquire requires requestService")
            }
            try operation.validate()
        case .subscribe(let requirementID, _):
            try ContractValidation.require(ContractValidation.identifier(requirementID), "Invalid requirement ID")
        case .unsubscribe: break
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(ServiceControlKind.self, forKey: .kind)
        var allowed: Set<String> = ["schemaVersion", "requestID", "kind"]
        switch kind {
        case .acquire: allowed.insert("operation")
        case .subscribe: allowed.formUnion(["requirementID", "grantID"])
        case .unsubscribe: allowed.insert("subscriptionID")
        }
        try SubscriptionWireValidation.fields(decoder, exactly: allowed)
        let action: ServiceControlAction
        switch kind {
        case .acquire: action = .acquire(try values.decode(OperationRequest.self, forKey: .operation))
        case .subscribe: action = .subscribe(requirementID: try values.decode(String.self, forKey: .requirementID),
                                             grantID: try values.decode(UUID.self, forKey: .grantID))
        case .unsubscribe: action = .unsubscribe(subscriptionID: try values.decode(UUID.self, forKey: .subscriptionID))
        }
        try self.init(schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
                      requestID: values.decode(UUID.self, forKey: .requestID), action: action)
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(requestID, forKey: .requestID)
        try values.encode(kind, forKey: .kind)
        switch action {
        case .acquire(let operation): try values.encode(operation, forKey: .operation)
        case .subscribe(let requirementID, let grantID):
            try values.encode(requirementID, forKey: .requirementID)
            try values.encode(grantID, forKey: .grantID)
        case .unsubscribe(let subscriptionID): try values.encode(subscriptionID, forKey: .subscriptionID)
        }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, requestID, kind, operation, requirementID, grantID, subscriptionID }
}
