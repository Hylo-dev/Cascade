import Foundation

/// Proposed syntax only; selecting this profile negotiates or authenticates nothing.
/// Runtime must select a profile from canonical negotiation after host integration.
public enum ServiceInvocationFrameProfile: Equatable, Sendable { case v1_3 }

/// Dedicated service bodies are bounded separately from generic AddonEvent.
/// Bounds describe wire values, not Foundation workspace or process memory.
public enum ServiceFrameCodec {
    /// Full 64 KiB base64 needs at most 174,768 bytes with every slash escaped.
    /// P1 metadata (UUIDs, 128-byte ASCII identifiers, finite numeric date and fixed
    /// keys) is below 8,192 bytes, so the total is below 192 KiB. Refusal reasons
    /// need at most 24,576 escaped bytes plus metadata and cannot coexist with payload.
    /// Outer transports must account for their own representation and envelope limit.
    public static let maximumEncodedBytes = 196_608
    public static let maximumPayloadBytes = 65_536
    public static let maximumFailureReasonBytes = 4_096

    public static func encode(_ request: ServiceInvocationRequest, profile: ServiceInvocationFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try request.validate()
        return try encodeValue(request)
    }

    public static func encode(_ reply: ServiceInvocationReply, profile: ServiceInvocationFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try reply.validate()
        return try encodeValue(reply)
    }

    public static func encode(_ frame: ServiceProviderFrame, profile: ServiceInvocationFrameProfile?) throws -> Data {
        try requireProfile(profile)
        try frame.validate()
        return try encodeValue(frame)
    }

    public static func decodeInvocationRequest(_ data: Data, profile: ServiceInvocationFrameProfile?) throws -> ServiceInvocationRequest {
        try requireFrameSize(data)
        try requireProfile(profile)
        let request = try JSONDecoder().decode(ServiceInvocationRequest.self, from: data)
        try request.validate()
        return request
    }

    public static func decodeInvocationReply(_ data: Data, profile: ServiceInvocationFrameProfile?) throws -> ServiceInvocationReply {
        try requireFrameSize(data)
        try requireProfile(profile)
        let reply = try JSONDecoder().decode(ServiceInvocationReply.self, from: data)
        try reply.validate()
        return reply
    }

    public static func decodeProviderFrame(_ data: Data, profile: ServiceInvocationFrameProfile?) throws -> ServiceProviderFrame {
        try requireFrameSize(data)
        try requireProfile(profile)
        let frame = try JSONDecoder().decode(ServiceProviderFrame.self, from: data)
        try frame.validate()
        return frame
    }

    private static func requireProfile(_ profile: ServiceInvocationFrameProfile?) throws {
        guard profile == .v1_3 else {
            throw AddonFailure(code: .versionConflict, reason: "Service frames require syntax profile 1.3")
        }
    }

    private static func requireFrameSize(_ data: Data) throws {
        try ContractValidation.require(data.count <= maximumEncodedBytes, "Service frame exceeds 192 KiB")
    }

    private static func encodeValue<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try requireFrameSize(data)
        return data
    }
}
