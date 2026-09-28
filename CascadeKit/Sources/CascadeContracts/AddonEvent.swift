//
//  AddonEvent.swift
//  CascadeKit
//

import Foundation

/// AddonEvent is the versioned provider input dispatched by the authenticated runtime.
public enum AddonEvent: Codable, Equatable, Sendable {
    case refresh(PublicationID)
    case scheduled(eventID: String)
    case action(ActionRequest)
    case serviceChanged(ServiceEvent)
    case serviceRequest(ServiceInvocation)
    case stop(StopReason)

    public var schemaVersion: Int { 1 }

    public func validate() throws {
        switch self {
        case .scheduled(let identifier):
            try ContractValidation.require(
                ContractValidation.identifier(identifier),
                "Invalid scheduled event ID"
            )
        case .action(let request): try request.validate()
        case .serviceChanged(let event): try event.validate()
        case .serviceRequest(let invocation): try invocation.validate()
        case .refresh, .stop: break
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        try ContractValidation.require(data.count <= 131_072, "Event exceeds 128 KiB")
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try ContractValidation.require(
            try values.decode(Int.self, forKey: .schemaVersion) == 1,
            "Unsupported event schema"
        )
        let kind = try values.decode(Kind.self, forKey: .kind)
        let fields = try decoder.container(keyedBy: WireKey.self)
        let allowed: Set<String>
        switch kind {
        case .refresh: allowed = ["schemaVersion", "kind", "publicationID"]
        case .scheduled: allowed = ["schemaVersion", "kind", "eventID"]
        case .action: allowed = ["schemaVersion", "kind", "request"]
        case .serviceChanged: allowed = ["schemaVersion", "kind", "event"]
        case .serviceRequest: allowed = ["schemaVersion", "kind", "invocation"]
        case .stop: allowed = ["schemaVersion", "kind", "reason"]
        }
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == allowed,
            "Invalid event fields"
        )
        switch kind {
        case .refresh: self = .refresh(try values.decode(PublicationID.self, forKey: .publicationID))
        case .scheduled: self = .scheduled(eventID: try values.decode(String.self, forKey: .eventID))
        case .action: self = .action(try values.decode(ActionRequest.self, forKey: .request))
        case .serviceChanged: self = .serviceChanged(try values.decode(ServiceEvent.self, forKey: .event))
        case .serviceRequest:
            self = .serviceRequest(try values.decode(ServiceInvocation.self, forKey: .invocation))
        case .stop: self = .stop(try values.decode(StopReason.self, forKey: .reason))
        }
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        switch self {
        case .refresh(let value):
            try values.encode(Kind.refresh, forKey: .kind)
            try values.encode(value, forKey: .publicationID)
        case .scheduled(let value):
            try values.encode(Kind.scheduled, forKey: .kind)
            try values.encode(value, forKey: .eventID)
        case .action(let value):
            try values.encode(Kind.action, forKey: .kind)
            try values.encode(value, forKey: .request)
        case .serviceChanged(let value):
            try values.encode(Kind.serviceChanged, forKey: .kind)
            try values.encode(value, forKey: .event)
        case .serviceRequest(let value):
            try values.encode(Kind.serviceRequest, forKey: .kind)
            try values.encode(value, forKey: .invocation)
        case .stop(let value):
            try values.encode(Kind.stop, forKey: .kind)
            try values.encode(value, forKey: .reason)
        }
    }
    private enum Kind: String, Codable {
        case refresh, scheduled, action, serviceChanged, serviceRequest, stop
    }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, publicationID, eventID, request, event, invocation, reason
    }
}
