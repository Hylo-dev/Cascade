//
//  KeyedStorageRecord.swift
//  CascadeKit
//

import CryptoKit
import Foundation

/// KeyedStorageRegistration describes trusted retained-data identity, including disabled addons.
struct KeyedStorageRegistration: Sendable {
    let identity : VerifiedAddonIdentity
}

/// KeyedStorageOwner is a canonical host capability, never decoded from provider input.
struct KeyedStorageOwner: Hashable, Sendable {
    let id : UUID
}

/// KeyedWriteTicket identifies the sole prepared write of one backend epoch.
struct KeyedWriteTicket: Hashable, Sendable {
    let id : UUID
}

/// KeyedStorageClass is host-selected; the eventual SDK facade always selects data.
enum KeyedStorageClass: UInt8, CaseIterable, Sendable {
    case data = 1
    case cache = 2

    var directoryName : String { self == .data ? "data" : "cache" }
    var maximumBytes  : Int { (self == .data ? 10 : 20) * 1_024 * 1_024 }
}

/// KeyedStorageFailure distinguishes precommit refusal from a visible but uncertain durable write.
enum KeyedStorageFailure: Error, Equatable, Sendable {
    case invalidConfiguration, invalidKey, oversized, invalidOwner, invalidTicket
    case closed, busy, unsafePath, unrecognizedEntry, corrupt, futureFormat
    case staleRevision, quotaExceeded, cleanupRequired, committedDurabilityUncertain
    case io(Int32)
}

/// KeyedStorageCloseStatus distinguishes immediate closure from an active operation draining its refunds.
enum KeyedStorageCloseStatus: Equatable, Sendable {
    case closed, draining
}

/// KeyedStorageRecord validates byte identity independently of Swift Unicode-equivalent String equality.
struct KeyedStorageRecord {
    static let maximumBytes           = 65_920
    static let headerBytes            = 128
    static let metadataBytes          = 4_096
    static let scratchBytes           = 267_776
    private static let magic          = Data("CASKV001".utf8)
    private static let checksumDomain = Data("Cascade.keyed.record.v1\0".utf8)

    let key      : Data
    let value    : Data
    let revision : UInt64
    let checksum : Data

    /// validatedKey bounds exact UTF-8 bytes without path interpretation or normalization.
    static func validatedKey(_ key: String) throws -> Data {
        guard (1...256).contains(key.utf8.count), !key.utf8.contains(0) else {
            throw KeyedStorageFailure.invalidKey
        }
        return Data(key.utf8)
    }

    /// namespaceDigest excludes executable digest so a verified same-publisher update retains its data.
    static func namespaceDigest(_ identity: VerifiedAddonIdentity) -> Data {
        var input     = Data("Cascade.keyed.namespace.v1\0".utf8)
        let publisher = Data(identity.publisher.utf8)
        appendInteger(
            UInt64(publisher.count),
            width : 8,
            to    : &input
        )
        input.append(publisher)
        let addon = Data(identity.addonID.rawValue.utf8)
        appendInteger(
            UInt64(addon.count),
            width : 8,
            to    : &input
        )
        input.append(addon)
        return Data(SHA256.hash(data: input))
    }

    /// keyDigest hashes exact key bytes in a separate domain from namespace and record checksums.
    static func keyDigest(_ key: Data) -> Data {
        var hash = SHA256()
        hash.update(data: Data("Cascade.keyed.key.v1\0".utf8))
        hash.update(data: key)
        return Data(hash.finalize())
    }

    /// hex creates the fixed lowercase filename component from a host-generated digest.
    static func hex(_ bytes: Data) -> String {
        bytes.map {
            String(
                format : "%02x",
                $0
            )
        }
        .joined()
    }

    /// encode creates a single bounded record only after caller-owned retention and scratch admission.
    static func encode(
        key          : Data,
        value        : Data,
        namespace    : Data,
        storageClass : KeyedStorageClass,
        revision     : UInt64
    ) -> Data {
        var header = magic
        appendInteger(
            1,
            width : 2,
            to    : &header
        )
        header.append(storageClass.rawValue)
        header.append(0)
        appendInteger(
            UInt64(key.count),
            width : 2,
            to    : &header
        )
        appendInteger(
            0,
            width : 2,
            to    : &header
        )
        appendInteger(
            UInt64(value.count),
            width : 4,
            to    : &header
        )
        appendInteger(
            0,
            width : 4,
            to    : &header
        )
        appendInteger(
            revision,
            width : 8,
            to    : &header
        )
        header.append(namespace)
        header.append(keyDigest(key))
        var hash = SHA256()
        hash.update(data: checksumDomain)
        hash.update(data: header)
        hash.update(data: key)
        hash.update(data: value)
        header.append(contentsOf: hash.finalize())
        header.append(key)
        header.append(value)
        return header
    }

    /// decode checks every binding before returning the opaque payload, including the raw key bytes.
    static func decode(
        _ bytes      : Data,
        key          : Data,
        namespace    : Data,
        storageClass : KeyedStorageClass
    ) throws -> KeyedStorageRecord {
        guard bytes.count <= maximumBytes else { throw KeyedStorageFailure.oversized }
        guard bytes.count >= headerBytes, bytes.prefix(8) == magic else {
            throw KeyedStorageFailure.corrupt
        }
        guard
            integer(
                bytes,
                offset : 8,
                width  : 2
            ) == 1
        else { throw KeyedStorageFailure.futureFormat }
        let keyCount = Int(
            integer(
                bytes,
                offset : 12,
                width  : 2
            )
        )
        let valueCount = Int(
            integer(
                bytes,
                offset : 16,
                width  : 4
            )
        )
        let revision = integer(
            bytes,
            offset : 24,
            width  : 8
        )
        guard bytes[10] == storageClass.rawValue, bytes[11] == 0,
            bytes[14..<16].allSatisfy({ $0 == 0 }), bytes[20..<24].allSatisfy({ $0 == 0 }),
            (1...256).contains(keyCount), valueCount <= 65_536, revision > 0,
            bytes.count == headerBytes + keyCount + valueCount,
            bytes[32..<64] == namespace, bytes[64..<96] == keyDigest(key),
            bytes[128..<(128 + keyCount)] == key
        else { throw KeyedStorageFailure.corrupt }
        var hash = SHA256()
        hash.update(data: checksumDomain)
        hash.update(data: bytes.prefix(96))
        hash.update(data: bytes.suffix(keyCount + valueCount))
        let checksum = Data(hash.finalize())
        guard checksum == bytes[96..<128] else { throw KeyedStorageFailure.corrupt }
        return KeyedStorageRecord(
            key      : key,
            value    : Data(bytes.suffix(valueCount)),
            revision : revision,
            checksum : checksum
        )
    }

    /// appendInteger writes a bounded unsigned field in big-endian order.
    private static func appendInteger(
        _ value : UInt64,
        width   : Int,
        to bytes: inout Data
    ) {
        for index in (0..<width).reversed() { bytes.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }

    /// integer reads a field only after the caller has checked the complete fixed header length.
    private static func integer(
        _ bytes : Data,
        offset  : Int,
        width   : Int
    ) -> UInt64 {
        bytes[offset..<(offset + width)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
