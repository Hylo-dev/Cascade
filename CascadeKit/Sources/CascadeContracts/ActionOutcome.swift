//
//  ActionOutcome.swift
//  Cascade
//

import Foundation

/// ActionOutcome is the final result; transport acceptance is deliberately not an outcome.
public enum ActionOutcome: Codable, Equatable, Sendable {
    case completed(payload: Data)
    case rejected(reason: AddonFailure)
    case outcomeUnknown

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(values.allKeys.count == 1, "Outcome requires exactly one discriminator")
        let discriminator = values.allKeys.first
        guard let discriminator else { throw AddonFailure(code: .invalidPayload, reason: "Missing outcome") }
        let fields = try values.nestedContainer(keyedBy: WireKey.self, forKey: discriminator)
        let allowed: Set<String>
        switch discriminator.stringValue {
        case "completed": allowed = ["payload"]
        case "rejected": allowed = ["reason"]
        case "outcomeUnknown": allowed = []
        default: throw AddonFailure(code: .invalidPayload, reason: "Unknown discriminator")
        }
        try ContractValidation.require(Set(fields.allKeys.map(\.stringValue)) == allowed, "Invalid result fields")
        let payload = try values.nestedContainer(keyedBy: PayloadKeys.self, forKey: discriminator)
        switch discriminator.stringValue {
        case "completed": self = .completed(payload: try payload.decode(Data.self, forKey: .payload))
        case "rejected": self = .rejected(reason: try payload.decode(AddonFailure.self, forKey: .reason))
        case "outcomeUnknown": self = .outcomeUnknown
        default: throw AddonFailure(code: .invalidPayload, reason: "Unknown outcome")
        }
        try validate()
    }

    public func validate() throws {
        switch self {
        case .completed(let payload):
            try ContractValidation.require(payload.count <= 65_536, "Action result exceeds 64 KiB")
        case .rejected(let reason):
            try reason.validate()
        case .outcomeUnknown:
            break
        }
    }
    private enum PayloadKeys: String, CodingKey { case payload, reason }
}
