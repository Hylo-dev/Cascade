//
//  StorageFrameCodec.swift
//  CascadeKit
//

import Foundation

/// StorageFrameProfile identifies implemented syntax, not handshake or access authority.
/// A transport must select it from its canonical negotiated protocol, never provider input.
public enum StorageFrameProfile: Equatable, Sendable {
    case v1_1
}

/// StorageFrameCodec bounds dedicated keyed-storage frames independently of generic
/// service payloads. Callers own and preadmit input, decoding workspace and output lifetimes.
/// These value bounds do not qualify Foundation parser workspace or whole-process memory.
public enum StorageFrameCodec {
    /// maximumEncodedBytes covers 174,768 slash-escaped base64 bytes, 1,536 escaped
    /// key bytes and 512 fixed bytes. Failure-only frames need at most 25,088 bytes.
    /// The enclosing transport must still enforce its total 512 KiB envelope limit.
    public static let maximumEncodedBytes       = 196_608
    public static let maximumValueBytes         = 65_536
    public static let maximumKeyBytes           = 256
    public static let maximumFailureReasonBytes = 4_096

    /// encode checks the profile and request before creating bounded JSON output.
    public static func encode(
        _ request: StorageRequest,
        profile  : StorageFrameProfile?
    ) throws -> Data {
        try requireProfile(profile)
        try request.validate()
        return try encodeValue(request)
    }

    /// encode checks the profile and response before creating bounded JSON output.
    public static func encode(
        _ response: StorageResponse,
        profile   : StorageFrameProfile?
    ) throws -> Data {
        try requireProfile(profile)
        try response.validate()
        return try encodeValue(response)
    }

    /// decodeRequest checks capability and raw size before Foundation interprets JSON.
    public static func decodeRequest(
        _ data : Data,
        profile: StorageFrameProfile?
    ) throws -> StorageRequest {
        try requireProfile(profile)
        try requireFrameSize(data)
        return try JSONDecoder().decode(
            StorageRequest.self,
            from: data
        )
    }

    /// decodeResponse checks capability and raw size before Foundation interprets JSON.
    public static func decodeResponse(
        _ data : Data,
        profile: StorageFrameProfile?
    ) throws -> StorageResponse {
        try requireProfile(profile)
        try requireFrameSize(data)
        return try JSONDecoder().decode(
            StorageResponse.self,
            from: data
        )
    }

    private static func requireProfile(_ profile: StorageFrameProfile?) throws {
        guard profile == .v1_1 else {
            throw AddonFailure(
                code  : .versionConflict,
                reason: "Keyed-storage frames require negotiated protocol 1.1"
            )
        }
    }

    private static func requireFrameSize(_ data: Data) throws {
        try ContractValidation.require(
            data.count <= maximumEncodedBytes,
            "Storage frame exceeds 192 KiB"
        )
    }

    /// encodeValue uses Foundation's standard base64 representation with stable key order.
    /// Input and output can coexist, so callers cannot assume encoding replaces its input charge.
    private static func encodeValue<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try requireFrameSize(data)
        return data
    }
}
