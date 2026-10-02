//
//  PluginRequirement.swift
//  CascadeKit
//

import Foundation

/// PluginRequirement is a condition outside Cascade that a plugin needs: another app
/// installed or running, or any one of a few such conditions. Everything inside Cascade is
/// declared per feature instead. Alternatives do not nest, which keeps the check a flat scan.
public indirect enum PluginRequirement: Codable, Equatable, Sendable {

    case appInstalled(bundleID: String)
    case appRunning(bundleID: String)
    case anyOf([PluginRequirement])

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
            case "appInstalled":
                self = .appInstalled(bundleID: try container.decode(String.self, forKey: .bundleID))

            case "appRunning":
                self = .appRunning(bundleID: try container.decode(String.self, forKey: .bundleID))

            case "anyOf":
                // Refused before the alternatives are decoded: nesting is invalid anyway, and
                // decoding it first would let a hostile manifest recurse to any depth.
                try ContractValidation.require(
                    !decoder.codingPath.contains { $0.stringValue == CodingKeys.alternatives.stringValue },
                    "anyOf alternatives cannot nest"
                )
                self = .anyOf(try container.decode([PluginRequirement].self, forKey: .alternatives))

            default:
                throw AddonFailure(code: .invalidPayload, reason: "Unknown requirement kind")
        }

        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
            case .appInstalled(let bundleID):
                try container.encode("appInstalled", forKey: .kind)
                try container.encode(bundleID, forKey: .bundleID)

            case .appRunning(let bundleID):
                try container.encode("appRunning", forKey: .kind)
                try container.encode(bundleID, forKey: .bundleID)

            case .anyOf(let alternatives):
                try container.encode("anyOf", forKey: .kind)
                try container.encode(alternatives, forKey: .alternatives)
        }
    }

    public func validate() throws {
        switch self {
            case .appInstalled(let bundleID), .appRunning(let bundleID):
                try ContractValidation.require(PluginID(rawValue: bundleID) != nil, "Invalid bundle ID")

            case .anyOf(let alternatives):
                try ContractValidation.require((2...8).contains(alternatives.count), "anyOf takes two to eight alternatives")
                try ContractValidation.require(
                    alternatives.allSatisfy { alternative in
                        if case .anyOf = alternative { false } else { true }
                    },
                    "anyOf alternatives cannot nest"
                )

                for alternative in alternatives {
                    try alternative.validate()
                }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case kind
        case bundleID
        case alternatives
    }
}
