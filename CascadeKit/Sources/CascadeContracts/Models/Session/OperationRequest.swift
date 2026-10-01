//
//  OperationRequest.swift
//  CascadeKit
//

import Foundation

/// OperationRequest expresses broker work without arbitrary Foundation objects.
public enum OperationRequest: Codable, Equatable, Sendable {

    case requestService(requirementID: String, scope: ServiceScope)
    case schedule      (deadline: Date, eventID: String)
    case releaseLease  (leaseID: UUID)
    case endPublication(PublicationID)

    /// validate checks values constructed in Swift before envelope admission.
    public func validate() throws {
        switch self {
            case .requestService(let identifier, let scope):
                try ContractValidation.require(
                    ContractValidation.identifier(identifier),
                    "Invalid requirement ID"
                )
                try scope.validate()

            case .schedule(let deadline, let identifier):
                try ContractValidation.finite(deadline)
                try ContractValidation.require(
                    ContractValidation.identifier(identifier),
                    "Invalid event ID"
                )

            case .releaseLease, .endPublication: break
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind   = try values.decode(Kind.self, forKey: .kind)
        let fields = try decoder.container(keyedBy: WireKey.self)
        let allowed: Set<String>
        switch kind {
            case .requestService: allowed = ["kind", "requirementID", "scope"]
            case .schedule      : allowed = ["kind", "deadline", "eventID"]
            case .releaseLease  : allowed = ["kind", "leaseID"]
            case .endPublication: allowed = ["kind", "publicationID"]
        }
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == allowed,
            "Invalid operation fields"
        )

        switch kind {
            case .requestService:
                let identifier = try values.decode(String.self, forKey: .requirementID)
                try ContractValidation.require(
                    ContractValidation.identifier(identifier),
                    "Invalid requirement ID"
                )

                self = .requestService(
                    requirementID: identifier,
                    scope        : try values.decode(ServiceScope.self, forKey: .scope)
                )

            case .schedule:
                let deadline   = try values.decode(Date.self, forKey: .deadline)
                let identifier = try values.decode(String.self, forKey: .eventID)
                try ContractValidation.finite(deadline)
                try ContractValidation.require(
                    ContractValidation.identifier(identifier),
                    "Invalid event ID"
                )

                self = .schedule(deadline: deadline, eventID: identifier)

            case .releaseLease:
                self = .releaseLease(leaseID: try values.decode(UUID.self, forKey: .leaseID))

            case .endPublication:
                self = .endPublication(try values.decode(PublicationID.self, forKey: .publicationID))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .requestService(let identifier, let scope):
                try values.encode(Kind.requestService, forKey: .kind)
                try values.encode(identifier, forKey: .requirementID)
                try values.encode(scope, forKey: .scope)

            case .schedule(let deadline, let identifier):
                try values.encode(Kind.schedule, forKey: .kind)
                try values.encode(deadline, forKey: .deadline)
                try values.encode(identifier, forKey: .eventID)

            case .releaseLease(let identifier):
                try values.encode(Kind.releaseLease, forKey: .kind)
                try values.encode(identifier, forKey: .leaseID)

            case .endPublication(let identifier):
                try values.encode(Kind.endPublication, forKey: .kind)
                try values.encode(identifier, forKey: .publicationID)
        }
    }

    private enum Kind: String, Codable {

        case requestService, schedule, releaseLease, endPublication
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case kind, requirementID, scope, deadline, eventID, leaseID, publicationID
    }
}
