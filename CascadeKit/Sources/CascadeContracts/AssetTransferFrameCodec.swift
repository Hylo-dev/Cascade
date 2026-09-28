//
//  AssetTransferFrameCodec.swift
//  Cascade
//

import Foundation

/// AssetTransferFrameProfile identifies implemented syntax, not handshake or access authority.
/// It makes no claim that a transport has negotiated or implemented asset transfer.
public enum AssetTransferFrameProfile: Equatable, Sendable {
    case v1
}

/// AssetTransferFrameCodec bounds dedicated asset-transfer frames independently of generic
/// service payloads. Callers own and preadmit input, decoding workspace and output lifetimes.
/// These value bounds do not qualify Foundation parser workspace or whole-process memory.
public enum AssetTransferFrameCodec {
    /// maximumEncodedBytes covers a 65,536-byte chunk: 87,384 base64 characters,
    /// at most 174,768 slash-escaped bytes plus 512 fixed bytes = 175,280.
    /// Failure reasons need at most 4,096 * 6 + 512 = 25,088 bytes.
    /// Begin has 8 semantic fields including its nested publication: 255 ASCII addon
    /// bytes + three 36-byte UUIDs + eight decimal bytes + 512 fixed = 883 bytes.
    /// Imported has 16 fields including handle/publication: two 255-byte addon IDs,
    /// four 36-byte UUIDs, 128 asset bytes, <=42 decimal bytes and 1,024 fixed = 1,848.
    /// Share/release add a nested source handle beside the target publication: at most
    /// two 128-byte addon/asset identifiers, two nested publications, four 36-byte UUIDs,
    /// <=84 decimal bytes and 1,536 fixed = under 3,072 bytes. The shared result carries
    /// only common fields plus a handle and stays under 1,848. All of these remain far
    /// below the 196,608-byte frame cap even with worst-case escaping of validated
    /// identifiers, so the cap is unchanged. Validated identifiers need no escaping. These conservative fixed allowances cover
    /// every key, punctuation and discriminant. The adapter still owes the 524,288-byte
    /// complete-envelope proof and separately admitted parser/copy workspace.
    public static let maximumEncodedBytes       = 196_608
    public static let maximumChunkBytes         = 65_536
    public static let maximumTotalBytes         = 1_048_576
    public static let maximumFailureReasonBytes = 4_096

    /// encode checks the profile and request before creating bounded JSON output.
    public static func encode(
        _ request: AssetTransferRequest,
        profile  : AssetTransferFrameProfile?
    ) throws -> Data {
        try requireProfile(profile)
        try request.validate()
        return try encodeValue(request)
    }

    /// encode checks the profile and response before creating bounded JSON output.
    public static func encode(
        _ response: AssetTransferResponse,
        profile   : AssetTransferFrameProfile?
    ) throws -> Data {
        try requireProfile(profile)
        try response.validate()
        return try encodeValue(response)
    }

    /// decodeRequest checks capability and raw size before Foundation interprets JSON.
    public static func decodeRequest(
        _ data : Data,
        profile: AssetTransferFrameProfile?
    ) throws -> AssetTransferRequest {
        try requireProfile(profile)
        try requireFrameSize(data)
        return try JSONDecoder().decode(
            AssetTransferRequest.self,
            from: data
        )
    }

    /// decodeResponse checks capability and raw size before Foundation interprets JSON.
    public static func decodeResponse(
        _ data : Data,
        profile: AssetTransferFrameProfile?
    ) throws -> AssetTransferResponse {
        try requireProfile(profile)
        try requireFrameSize(data)
        return try JSONDecoder().decode(
            AssetTransferResponse.self,
            from: data
        )
    }

    private static func requireProfile(_ profile: AssetTransferFrameProfile?) throws {
        guard profile == .v1 else {
            throw AddonFailure(
                code  : .versionConflict,
                reason: "Asset frames require an explicit supported syntax profile"
            )
        }
    }

    private static func requireFrameSize(_ data: Data) throws {
        try ContractValidation.require(
            data.count <= maximumEncodedBytes,
            "Asset frame exceeds 192 KiB"
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
