import Foundation

/// Pure syntax selection neither negotiates nor authenticates a channel.
public enum ServiceSubscriptionFrameProfile: Equatable, Sendable { case v1_4 }

/// Separate control/source/event bodies. Invocation P1 and generic event codecs
/// remain unchanged. These bounds do not describe allocator workspace or RSS.
public enum ServiceSubscriptionFrameCodec {
    /// All-slash-escaped 64 KiB base64 <=174,768 bytes plus metadata <8,192.
    /// Publisher/digest/partition total <=1,024 UTF-8 bytes, <=6,144 JSON-escaped
    /// bytes. Refusal reason <=24,576 escaped bytes and never shares a payload.
    /// The outer transport must account for its own envelope representation.
    public static let maximumEncodedBytes = 196_608
    public static let maximumPayloadBytes = 65_536
    public static let maximumFailureReasonBytes = 4_096

    public static func encode(_ request: ServiceControlRequest, profile: ServiceSubscriptionFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try request.validate()
        return try encodeValue(request)
    }
    public static func encode(_ reply: ServiceControlReply, profile: ServiceSubscriptionFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try reply.validate()
        return try encodeValue(reply)
    }
    public static func encode(_ start: ServiceSourceStartFrame, profile: ServiceSubscriptionFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try start.validate()
        return try encodeValue(start)
    }
    public static func encode(_ output: ServiceSourceOutputFrame, profile: ServiceSubscriptionFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try output.validate()
        return try encodeValue(output)
    }
    public static func encode(_ event: ServiceEvent, profile: ServiceSubscriptionFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try event.validate()
        try SubscriptionWireValidation.grant(event.token)
        return try encodeValue(event)
    }

    public static func decodeControlRequest(_ data: Data, profile: ServiceSubscriptionFrameProfile?) throws -> ServiceControlRequest {
        try requireIngress(data, profile: profile)
        let value = try JSONDecoder().decode(ServiceControlRequest.self, from: data)
        try value.validate()
        return value
    }
    public static func decodeControlReply(_ data: Data, profile: ServiceSubscriptionFrameProfile?) throws -> ServiceControlReply {
        try requireIngress(data, profile: profile)
        let value = try JSONDecoder().decode(ServiceControlReply.self, from: data)
        try value.validate()
        return value
    }
    public static func decodeSourceStart(_ data: Data, profile: ServiceSubscriptionFrameProfile?) throws -> ServiceSourceStartFrame {
        try requireIngress(data, profile: profile)
        let value = try JSONDecoder().decode(ServiceSourceStartFrame.self, from: data)
        try value.validate()
        return value
    }
    public static func decodeSourceOutput(_ data: Data, profile: ServiceSubscriptionFrameProfile?) throws -> ServiceSourceOutputFrame {
        try requireIngress(data, profile: profile)
        let value = try JSONDecoder().decode(ServiceSourceOutputFrame.self, from: data)
        try value.validate()
        return value
    }
    public static func decodeServiceEvent(_ data: Data, profile: ServiceSubscriptionFrameProfile?) throws -> ServiceEvent {
        try requireIngress(data, profile: profile)
        return try JSONDecoder().decode(StrictEvent.self, from: data).value
    }

    private static func requireProfile(_ profile: ServiceSubscriptionFrameProfile?) throws {
        guard profile == .v1_4 else {
            throw AddonFailure(code: .versionConflict, reason: "Subscription frames require syntax profile 1.4")
        }
    }
    private static func requireSize(_ data: Data) throws {
        try ContractValidation.require(data.count <= maximumEncodedBytes, "Subscription frame exceeds 192 KiB")
    }
    private static func requireIngress(_ data: Data, profile: ServiceSubscriptionFrameProfile?) throws {
        // Original raw count is checked before profile selection or Foundation decode.
        try requireSize(data)
        try requireProfile(profile)
    }
    private static func encodeValue<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try requireSize(data)
        return data
    }

    private struct StrictEvent: Decodable {
        let value: ServiceEvent
        init(from decoder: any Decoder) throws {
            // Reuse the existing closed event/response contracts, supplementing only
            // the generation field whose existing synthesized decoder is open.
            let fields = try decoder.container(keyedBy: EventKeys.self)
            _ = try fields.decode(SubscriptionStrictGrant.self, forKey: .token)
            value = try ServiceEvent(from: decoder)
            try value.validate()
        }
        private enum EventKeys: String, CodingKey { case token }
    }
}

/// Shared only by the new syntax; no change to existing nested DTO decoders.
enum SubscriptionWireValidation {
    static func fields(_ decoder: any Decoder, exactly allowed: Set<String>) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(Set(fields.allKeys.map(\.stringValue)) == allowed, "Invalid subscription wire fields")
    }
    static func grant(_ value: Grant) throws {
        try value.validate()
        try value.scope.validate()
        try value.cost.validate()
    }
}

struct SubscriptionStrictGrant: Decodable {
    let value: Grant
    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        let generation = try fields.superDecoder(forKey: .generation)
        try SubscriptionWireValidation.fields(generation, exactly: ["value"])
        value = try Grant(from: decoder)
        try SubscriptionWireValidation.grant(value)
    }
    private enum Keys: String, CodingKey { case generation }
}
