//
//  ServiceSourceOutputFrame.swift
//  CascadeKit
//

import Foundation

public enum ServiceSourceOutput: Equatable, Sendable {
    case startupCompleted
    case sourceUpdate(ServiceResponse)
}

/// ServiceSourceOutputFrame is the dedicated provider output syntax; canonical
/// source lifetime and readiness are external checks. Startup completion carries
/// no response or update authority.
public struct ServiceSourceOutputFrame: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceID: UUID
    public let startNonce: UUID
    public let output: ServiceSourceOutput

    public init(schemaVersion: Int = 1, sourceID: UUID, startNonce: UUID, output: ServiceSourceOutput) throws {
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.startNonce = startNonce
        self.output = output
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported source output schema")
        if case .sourceUpdate(let response) = output { try response.validate() }
    }

    public func validate(matching start: ServiceSourceStartFrame) throws {
        try validate()
        try start.validate()
        try ContractValidation.require(sourceID == start.sourceID && startNonce == start.startNonce, "Source output start mismatch")
        if case .sourceUpdate(let response) = output {
            try ContractValidation.require(response.contractID == start.serviceID && response.operation == start.scope.operation,
                                           "Source response descriptor mismatch")
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(String.self, forKey: .kind)
        var allowed: Set<String> = ["schemaVersion", "kind", "sourceID", "startNonce"]
        switch kind {
        case "startupCompleted": break
        case "sourceUpdate": allowed.insert("response")
        default: throw AddonFailure(code: .invalidPayload, reason: "Unknown source output kind")
        }
        try SubscriptionWireValidation.fields(decoder, exactly: allowed)
        let output: ServiceSourceOutput = kind == "startupCompleted" ? .startupCompleted : .sourceUpdate(try values.decode(ServiceResponse.self, forKey: .response))
        try self.init(schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
                      sourceID: values.decode(UUID.self, forKey: .sourceID), startNonce: values.decode(UUID.self, forKey: .startNonce), output: output)
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(sourceID, forKey: .sourceID)
        try values.encode(startNonce, forKey: .startNonce)
        switch output {
        case .startupCompleted: try values.encode("startupCompleted", forKey: .kind)
        case .sourceUpdate(let response):
            try values.encode("sourceUpdate", forKey: .kind)
            try values.encode(response, forKey: .response)
        }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, kind, sourceID, startNonce, response }
}
