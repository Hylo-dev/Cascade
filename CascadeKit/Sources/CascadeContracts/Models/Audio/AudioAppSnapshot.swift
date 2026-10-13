//
//  AudioAppSnapshot.swift
//  CascadeKit
//

import Foundation

/// AudioAppSnapshot is AudioHost's report on one app that is producing audio: the intent it
/// was told, how it is enforcing it and where the sound actually goes. The intent is echoed back
/// so the mixer can tell a settled app from one whose last command is still in flight.
public struct AudioAppSnapshot: Codable, Equatable, Sendable {

    public static let maximumDisplayNameBytes = 256

    public let identity           : AudioAppIdentity
    public let displayName        : String
    public let intent             : AudioAppIntent
    public let enforcement        : AudioAppEnforcement
    public let effectiveOutputUIDs: [String]

    public init(
        identity           : AudioAppIdentity,
        displayName        : String,
        intent             : AudioAppIntent,
        enforcement        : AudioAppEnforcement,
        effectiveOutputUIDs: [String]
    ) throws {
        self.identity            = identity
        self.displayName         = displayName
        self.intent              = intent
        self.enforcement         = enforcement
        self.effectiveOutputUIDs = effectiveOutputUIDs

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container       = try decoder.container(keyedBy: CodingKeys.self)
        identity            = try container.decode(AudioAppIdentity.self, forKey: .identity)
        displayName         = try container.decode(String.self, forKey: .displayName)
        intent              = try container.decode(AudioAppIntent.self, forKey: .intent)
        enforcement         = try container.decode(AudioAppEnforcement.self, forKey: .enforcement)
        effectiveOutputUIDs = try container.decode([String].self, forKey: .effectiveOutputUIDs)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            displayName.utf8.count <= Self.maximumDisplayNameBytes,
            "Audio app name too long"
        )
        try ContractValidation.require(
            effectiveOutputUIDs.count <= AudioAppIntent.maximumOutputs
                && effectiveOutputUIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= AudioAppIntent.maximumUIDBytes },
            "Invalid effective audio outputs"
        )
        try ContractValidation.unique(effectiveOutputUIDs, "Duplicate effective audio outputs")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case identity
        case displayName
        case intent
        case enforcement
        case effectiveOutputUIDs
    }
}
