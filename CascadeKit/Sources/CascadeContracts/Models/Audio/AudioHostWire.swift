//
//  AudioHostWire.swift
//  CascadeKit
//

import Foundation

/// AudioHostWire is the one place AudioHost's JSON payloads are made and read. Both ends of the
/// XPC connection go through it, so the size limit and the validation of every model apply to
/// each message the same way: a payload over 64 KiB, malformed, carrying an unknown field or
/// failing a model's own rules throws and is dropped, never half-applied.
public enum AudioHostWire {

    public static let maximumBytes = 65_536

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        try ContractValidation.require(data.count <= maximumBytes, "Audio payload exceeds byte limit")

        return data
    }

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        try ContractValidation.require(data.count <= maximumBytes, "Audio payload exceeds byte limit")

        return try JSONDecoder().decode(type, from: data)
    }
}
