//
//  PluginActionEvent.swift
//  CascadeKit
//

import Foundation

/// PluginActionEvent tells a plugin that the user activated one of its controls, or that Cascade
/// invoked one of its declared actions for the user, such as a preview. The kernel builds it from
/// the control it found in the published document or from the declaration, so a plugin only ever
/// receives an action it named. `value` is a toggle's new state or a slider's
/// released value, and absent for a button.
public struct PluginActionEvent: Codable, Equatable, Sendable {

    public let feature: String
    public let action : String
    public let value  : PluginValue?

    public init(
        feature: String,
        action : String,
        value  : PluginValue? = nil
    ) throws {
        self.feature = feature
        self.action  = action
        self.value   = value

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        feature       = try container.decode(String.self, forKey: .feature)
        action        = try container.decode(String.self, forKey: .action)
        value         = try container.decodeIfPresent(PluginValue.self, forKey: .value)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(ContractValidation.identifier(feature), "Invalid feature ID")
        try ContractValidation.require(ContractValidation.identifier(action), "Invalid action ID")

        switch value {
            case .bool?, nil:
                break

            case .number(let number)?:
                try ContractValidation.require(number.isFinite, "Action numbers must be finite")

            case .string?:
                throw AddonFailure(code: .invalidPayload, reason: "A control never sends text")
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case feature
        case action
        case value
    }
}
