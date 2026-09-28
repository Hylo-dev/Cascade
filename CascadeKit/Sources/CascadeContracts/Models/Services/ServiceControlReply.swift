//
//  ServiceControlReply.swift
//  CascadeKit
//

import Foundation

public struct ServiceControlReply: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let kind: ServiceControlKind
    public let phase: ServiceControlPhase
    public let result: ServiceControlResult

    public init(schemaVersion: Int = 1, requestID: UUID, kind: ServiceControlKind,
                phase: ServiceControlPhase, result: ServiceControlResult) throws {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.kind = kind
        self.phase = phase
        self.result = result
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported service control schema")
        let legal: Bool
        switch (phase, kind, result) {
        case (.admission, .acquire, .accepted), (.terminal, .acquire, .acquired),
             (.terminal, .subscribe, .subscribed), (.terminal, .unsubscribe, .acknowledged),
             (.terminal, _, .refused), (.terminal, _, .outcomeUnknown): legal = true
        default: legal = false
        }
        try ContractValidation.require(legal, "Invalid service control phase/result/kind")
        switch result {
        case .acquired(let grant): try SubscriptionWireValidation.grant(grant)
        case .refused(let code, let reason):
            try ContractValidation.require(code != .outcomeUnknown, "Refused result cannot carry outcomeUnknown")
            // Check original UTF-8 without AddonFailure's convenience truncation.
            try ContractValidation.require(!reason.isEmpty && reason.utf8.count <= ServiceSubscriptionFrameCodec.maximumFailureReasonBytes,
                                           "Invalid service failure reason")
        case .accepted, .subscribed, .acknowledged, .outcomeUnknown: break
        }
    }

    /// validate(matching:) checks the reply against the request it answers;
    /// binding names need not equal service IDs. Owner, current generation and
    /// canonical authority checks remain host/channel responsibilities.
    public func validate(matching request: ServiceControlRequest) throws {
        try validate()
        try request.validate()
        try ContractValidation.require(requestID == request.requestID && kind == request.kind, "Service control reply request mismatch")
        if case .acquired(let grant) = result, case .acquire(.requestService(_, let scope)) = request.action {
            try ContractValidation.require(grant.scope == scope, "Service control grant scope mismatch")
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let discriminator = try values.decode(String.self, forKey: .result)
        var allowed: Set<String> = ["schemaVersion", "requestID", "kind", "phase", "result"]
        switch discriminator {
        case "acquired": allowed.insert("grant")
        case "subscribed": allowed.insert("subscriptionID")
        case "refused": allowed.formUnion(["failureCode", "failureReason"])
        case "accepted", "acknowledged", "outcomeUnknown": break
        default: throw AddonFailure(code: .invalidPayload, reason: "Unknown service control result")
        }
        try SubscriptionWireValidation.fields(decoder, exactly: allowed)
        let result: ServiceControlResult
        switch discriminator {
        case "accepted": result = .accepted
        case "acquired": result = .acquired(try values.decode(SubscriptionStrictGrant.self, forKey: .grant).value)
        case "subscribed": result = .subscribed(try values.decode(UUID.self, forKey: .subscriptionID))
        case "acknowledged": result = .acknowledged
        case "refused":
            let raw = try values.decode(String.self, forKey: .failureCode)
            guard let code = AddonFailure.Code(rawValue: raw) else {
                throw AddonFailure(code: .invalidPayload, reason: "Unknown service failure code")
            }
            result = .refused(code: code, reason: try values.decode(String.self, forKey: .failureReason))
        default: result = .outcomeUnknown // Closed discriminator above.
        }
        try self.init(schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
                      requestID: values.decode(UUID.self, forKey: .requestID),
                      kind: values.decode(ServiceControlKind.self, forKey: .kind),
                      phase: values.decode(ServiceControlPhase.self, forKey: .phase), result: result)
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(requestID, forKey: .requestID)
        try values.encode(kind, forKey: .kind)
        try values.encode(phase, forKey: .phase)
        switch result {
        case .accepted: try values.encode("accepted", forKey: .result)
        case .acquired(let grant):
            try values.encode("acquired", forKey: .result)
            try values.encode(grant, forKey: .grant)
        case .subscribed(let subscriptionID):
            try values.encode("subscribed", forKey: .result)
            try values.encode(subscriptionID, forKey: .subscriptionID)
        case .acknowledged: try values.encode("acknowledged", forKey: .result)
        case .refused(let code, let reason):
            try values.encode("refused", forKey: .result)
            try values.encode(code, forKey: .failureCode)
            try values.encode(reason, forKey: .failureReason)
        case .outcomeUnknown: try values.encode("outcomeUnknown", forKey: .result)
        }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, requestID, kind, phase, result, grant, subscriptionID, failureCode, failureReason }
}
