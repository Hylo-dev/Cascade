//
//  RuntimeArchiveEnvelope.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeArchiveEnvelope contains inert host archive values, never provider or pixel authority.
struct RuntimeArchiveEnvelope: Equatable, Sendable {

    let publisher: Data
    let addon    : Data
    let digest   : Data
    let records  : [Record]
    let blobs    : [Blob]

    /// Record preserves one live publication or terminal session history with host provenance.
    struct Record: Equatable, Sendable {

        let instance       : Data
        let session        : Data
        let feature        : Data
        let partition      : Data?
        let revision       : UInt64
        let kind           : Publication.Kind
        let sessionDeadline: Date
        let publication    : Data?
        let aliases        : [Alias]
    }

    /// Alias maps a publication-local label to an inert blob ID within the same archived partition.
    struct Alias: Equatable, Sendable {

        let name: Data
        let blob: Data
    }

    /// Blob stores one checked tightly packed RGBA8 raster, deduplicated within its partition.
    struct Blob: Equatable, Sendable {

        let id       : Data
        let partition: Data?
        let width    : Int
        let height   : Int
        let pixels   : Data
    }

    static let maximumPayloadBytes = 8 * 1_024 * 1_024
    static let maximumRecords      = 16
    static let maximumAliases      = 8_192
    static let maximumBlobs        = AssetDisposalCoordinator.maximumSlots

    /// retentionReservationBytes must be admitted before decoding any table or leaf and held until
    /// all envelope references disappear. Decode additionally requires data.count scalar scratch.
    /// The backend's own read scope does not pay for these caller-retained tables or leaves.
    static func retentionReservationBytes() throws -> Int {
        try RuntimeArchiveCost.add(
            maximumPayloadBytes,
            metadataBytes(
                records: maximumRecords,
                aliases: maximumAliases,
                blobs  : maximumBlobs
            )
        )
    }

    /// metadataBytes derives M; leaves and temporary scalar decode overlap are separate charges.
    static func metadataBytes(
        records: Int,
        aliases: Int,
        blobs  : Int
    ) throws -> Int {
        try RuntimeArchiveCost.require(
            records <= maximumRecords && aliases <= maximumAliases && blobs <= maximumBlobs
        )

        var bytes = 65_536
        bytes     = try RuntimeArchiveCost.add(bytes, RuntimeArchiveCost.multiply(records, 4_096))
        bytes     = try RuntimeArchiveCost.add(bytes, RuntimeArchiveCost.multiply(aliases, 1_024))

        return try RuntimeArchiveCost.add(bytes, RuntimeArchiveCost.multiply(blobs, 1_024))
    }

    /// decode accepts only binary plists and performs no recursive Publication decoding.
    /// The caller prepays retentionReservationBytes plus one input-sized scalar scratch slot.
    static func decode(_ data: Data) throws -> Self {
        try RuntimeArchiveCost.require(
            data.count <= maximumPayloadBytes && data.starts(with: Data("bplist00".utf8))
        )

        return try PropertyListDecoder().decode(Wire.self, from: data).value
    }

    /// encode requires caller-owned envelope memory and encoding workspace through output consumption.
    /// encodingReservationBytes includes output capacity and conservative controlled scalar overlap.
    func encode() throws -> Data {
        try validate()

        let encoder          = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data             = try encoder.encode(Wire(value: self))
        try RuntimeArchiveCost.require(data.count <= Self.maximumPayloadBytes)

        return data
    }

    /// encodingReservationBytes requires existing envelope retention protection during validation.
    func encodingReservationBytes() throws -> Int {
        try validate()

        return try RuntimeArchiveCost.add(
            Self.maximumPayloadBytes,
            RuntimeArchiveCost.add(
                leafBytes(),
                Self.metadataBytes(
                    records: records.count,
                    aliases: records.reduce(0) { $0 + $1.aliases.count },
                    blobs  : blobs.count
                )
            )
        )
    }

    /// uuidBytes preserves UUID octets without allocating an unbounded textual scalar.
    static func uuidBytes(_ uuid: UUID) -> Data {
        var value = uuid.uuid

        return withUnsafeBytes(of: &value) { Data($0) }
    }

    /// uuid reconstructs a fixed-size label; it never grants authority or reuses a live partition.
    static func uuid(_ data: Data) throws -> UUID {
        try RuntimeArchiveCost.require(data.count == 16)

        let bytes = Array(data)

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    /// validate checks shallow ownership and relationships only. B2 separately authenticates current
    /// host provenance and validates each decoded Publication through validateBinding before activation.
    func validate() throws {
        try RuntimeArchiveCost.require(
            records.count <= Self.maximumRecords && blobs.count <= Self.maximumBlobs
        )

        _ = try Self.text(publisher, maximum: 512)
        _ = try Self.text(digest, maximum: 512)

        let addonName = try Self.text(addon, maximum: 255)
        try RuntimeArchiveCost.require(AddonID(rawValue: addonName) != nil)

        _ = try leafBytes()

        var blobByID: [Data: Blob] = [:]
        for blob in blobs {
            try RuntimeArchiveCost.require(blob.id.count == 16 && blobByID[blob.id] == nil)
            try Self.validatePartition(blob.partition)
            _ = try AssetRasterLayout(
                width    : blob.width,
                height   : blob.height,
                byteCount: blob.pixels.count
            )
            blobByID[blob.id] = blob
        }

        var instances  = Set<Data>()
        var usedBlobs  = Set<Data>()
        var aliasCount = 0
        for record in records {
            try RuntimeArchiveCost.require(
                record.instance.count == 16 && record.session.count == 16
                    && instances.insert(record.instance).inserted && record.kind != .notice
                    && record.sessionDeadline.timeIntervalSinceReferenceDate.isFinite
                    && (record.publication != nil || record.aliases.isEmpty)
                    && (record.publication?.count ?? 0)
                        <= RuntimeArchivePublicationCodec.maximumPublicationBytes
            )
            try Self.validateIdentifier(record.feature)
            try Self.validatePartition(record.partition)

            aliasCount = try RuntimeArchiveCost.add(aliasCount, record.aliases.count)
            try RuntimeArchiveCost.require(aliasCount <= Self.maximumAliases)

            var names = Set<Data>()
            for alias in record.aliases {
                try Self.validateIdentifier(alias.name)
                try RuntimeArchiveCost.require(alias.blob.count == 16 && names.insert(alias.name).inserted)
                guard let blob = blobByID[alias.blob] else {
                    throw AddonFailure(
                        code  : .invalidPayload,
                        reason: "Dangling archive raster alias"
                    )
                }

                try RuntimeArchiveCost.require(blob.partition == record.partition)
                usedBlobs.insert(alias.blob)
            }
        }

        try RuntimeArchiveCost.require(usedBlobs.count == blobs.count)
    }

    /// leafBytes counts occurrences, including repeated references to one binary-plist Data object.
    func leafBytes() throws -> Int {
        var bytes = 0

        func add(_ data: Data?) throws {
            bytes = try RuntimeArchiveCost.add(bytes, data?.count ?? 0)
            try RuntimeArchiveCost.require(bytes <= Self.maximumPayloadBytes)
        }

        try add(publisher)
        try add(addon)
        try add(digest)

        for record in records {
            try add(record.instance)
            try add(record.session)
            try add(record.feature)
            try add(record.partition)
            try add(record.publication)
            for alias in record.aliases {
                try add(alias.name)
                try add(alias.blob)
            }
        }

        for blob in blobs {
            try add(blob.id)
            try add(blob.partition)
            try add(blob.pixels)
        }

        return bytes
    }

    /// text validates the UTF-8 byte bound before constructing a metadata String.
    static func text(
        _ data : Data,
        maximum: Int
    ) throws -> String {
        try RuntimeArchiveCost.require(!data.isEmpty && data.count <= maximum)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Invalid archive UTF-8"
            )
        }

        return text
    }

    private static func validateIdentifier(_ data: Data) throws {
        let value = try text(data, maximum: 128)
        try RuntimeArchiveCost.require(
            value.range(of: "^[a-zA-Z][a-zA-Z0-9_.-]*$", options: .regularExpression) != nil
        )
    }

    private static func validatePartition(_ data: Data?) throws {
        try RuntimeArchiveCost.require(data == nil || data?.count == 16)
    }

    private struct Budget {

        var leaves  = 0
        var aliases = 0
    }

    /// tuple checks exact positional row size before any value is materialized. There are no
    /// input-dependent key arrays: version 1 consists solely of fixed rows and bounded leaf arrays.
    private static func tuple(
        _ decoder: any Decoder,
        count    : Int
    ) throws -> any UnkeyedDecodingContainer {
        let values = try decoder.unkeyedContainer()
        try RuntimeArchiveCost.require(values.count.map { $0 == count } ?? true)

        return values
    }

    /// leaf checks declared bytes against both per-scalar and aggregate limits before decoding Data.
    /// A false declaration can materialize only one input-sized scalar before being rejected.
    private static func leaf(
        _ decoder: any Decoder,
        maximum  : Int,
        budget   : inout Budget
    ) throws -> Data {
        var values = try tuple(decoder, count: 2)

        let declared = try values.decode(Int.self)
        try RuntimeArchiveCost.require(declared >= 0 && declared <= maximum)

        let next = try RuntimeArchiveCost.add(budget.leaves, declared)
        try RuntimeArchiveCost.require(next <= maximumPayloadBytes)

        let bytes = try values.decode(Data.self)
        try RuntimeArchiveCost.require(bytes.count == declared && values.isAtEnd)
        budget.leaves = next

        return bytes
    }

    /// optionalLeaf traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func optionalLeaf(
        _ decoder: any Decoder,
        maximum  : Int,
        budget   : inout Budget
    ) throws -> Data? {
        let values = try decoder.unkeyedContainer()
        if values.isAtEnd { return nil }

        return try leaf(
            decoder,
            maximum: maximum,
            budget : &budget
        )
    }

    /// array checks known count before reserve and unknown count before each shallow member.
    private static func array<Value>(
        _ decoder: any Decoder,
        maximum  : Int,
        budget   : inout Budget,
        read     : (any Decoder, inout Budget) throws -> Value
    ) throws -> [Value] {
        var values = try decoder.unkeyedContainer()
        try RuntimeArchiveCost.require(values.count.map { $0 <= maximum } ?? true)

        var result: [Value] = []
        if let count = values.count { result.reserveCapacity(count) }
        while !values.isAtEnd {
            try RuntimeArchiveCost.require(result.count < maximum)
            result.append(try read(values.superDecoder(), &budget))
        }

        return result
    }

    private struct Leaf: Encodable {

        let bytes: Data?

        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            if let bytes {
                try values.encode(bytes.count)
                try values.encode(bytes)
            }
        }
    }

    /// Wire is the version 1 positional root: schema, publisher, addon, digest, records, blobs.
    private struct Wire: Codable {

        let value: RuntimeArchiveEnvelope

        init(value: RuntimeArchiveEnvelope) { self.value = value }

        init(from decoder: any Decoder) throws {
            var values = try tuple(decoder, count: 6)
            try RuntimeArchiveCost.require(try values.decode(Int.self) == 1)

            var budget    = Budget()
            let publisher = try leaf(
                values.superDecoder(),
                maximum: 512,
                budget : &budget
            )
            let addon     = try leaf(
                values.superDecoder(),
                maximum: 255,
                budget : &budget
            )
            let digest    = try leaf(
                values.superDecoder(),
                maximum: 512,
                budget : &budget
            )
            let records   = try array(
                values.superDecoder(),
                maximum: maximumRecords,
                budget : &budget,
                read   : readRecord
            )
            let blobs     = try array(
                values.superDecoder(),
                maximum: maximumBlobs,
                budget : &budget,
                read   : readBlob
            )
            try RuntimeArchiveCost.require(values.isAtEnd)

            value = RuntimeArchiveEnvelope(
                publisher: publisher,
                addon    : addon,
                digest   : digest,
                records  : records,
                blobs    : blobs
            )
            try value.validate()
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(1)
            try values.encode(Leaf(bytes: value.publisher))
            try values.encode(Leaf(bytes: value.addon))
            try values.encode(Leaf(bytes: value.digest))

            var records = values.nestedUnkeyedContainer()
            for record in value.records {
                try writeRecord(record, to: records.superEncoder())
            }

            var blobs = values.nestedUnkeyedContainer()
            for blob in value.blobs {
                try writeBlob(blob, to: blobs.superEncoder())
            }
        }
    }

    /// readRecord traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func readRecord(
        _ decoder: any Decoder,
        budget   : inout Budget
    ) throws -> Record {
        var values = try tuple(decoder, count: 9)

        let instance  = try leaf(
            values.superDecoder(),
            maximum: 16,
            budget : &budget
        )
        let session   = try leaf(
            values.superDecoder(),
            maximum: 16,
            budget : &budget
        )
        let feature   = try leaf(
            values.superDecoder(),
            maximum: 128,
            budget : &budget
        )
        let partition = try optionalLeaf(
            values.superDecoder(),
            maximum: 16,
            budget : &budget
        )

        let revision = try values.decode(UInt64.self)
        let kindCode = try values.decode(Int.self)
        try RuntimeArchiveCost.require(kindCode == 0 || kindCode == 1)

        let kind           : Publication.Kind = kindCode == 0 ? .widget : .activity
        let sessionDeadline = Date(timeIntervalSinceReferenceDate: try values.decode(Double.self))
        let publication     = try optionalLeaf(
            values.superDecoder(),
            maximum: 266240,
            budget : &budget
        )
        let aliases         = try array(
            values.superDecoder(),
            maximum: maximumAliases - budget.aliases,
            budget : &budget,
            read   : readAlias
        )
        try RuntimeArchiveCost.require(values.isAtEnd)

        return Record(
            instance       : instance,
            session        : session,
            feature        : feature,
            partition      : partition,
            revision       : revision,
            kind           : kind,
            sessionDeadline: sessionDeadline,
            publication    : publication,
            aliases        : aliases
        )
    }

    /// writeRecord traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func writeRecord(
        _ value   : Record,
        to encoder: any Encoder
    ) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(Leaf(bytes: value.instance))
        try values.encode(Leaf(bytes: value.session))
        try values.encode(Leaf(bytes: value.feature))
        try values.encode(Leaf(bytes: value.partition))
        try values.encode(value.revision)
        try values.encode(value.kind == .widget ? 0 : 1)
        try values.encode(value.sessionDeadline.timeIntervalSinceReferenceDate)
        try values.encode(Leaf(bytes: value.publication))

        var aliases = values.nestedUnkeyedContainer()
        for alias in value.aliases {
            try writeAlias(alias, to: aliases.superEncoder())
        }
    }

    /// readAlias traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func readAlias(
        _ decoder: any Decoder,
        budget   : inout Budget
    ) throws -> Alias {
        var values = try tuple(decoder, count: 2)
        try RuntimeArchiveCost.require(budget.aliases < maximumAliases)
        budget.aliases += 1

        let name = try leaf(
            values.superDecoder(),
            maximum: 128,
            budget : &budget
        )
        let blob = try leaf(
            values.superDecoder(),
            maximum: 16,
            budget : &budget
        )
        try RuntimeArchiveCost.require(values.isAtEnd)

        return Alias(name: name, blob: blob)
    }

    /// writeAlias traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func writeAlias(
        _ value   : Alias,
        to encoder: any Encoder
    ) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(Leaf(bytes: value.name))
        try values.encode(Leaf(bytes: value.blob))
    }

    /// readBlob traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func readBlob(
        _ decoder: any Decoder,
        budget   : inout Budget
    ) throws -> Blob {
        var values = try tuple(decoder, count: 5)

        let id        = try leaf(
            values.superDecoder(),
            maximum: 16,
            budget : &budget
        )
        let partition = try optionalLeaf(
            values.superDecoder(),
            maximum: 16,
            budget : &budget
        )

        let width      = try values.decode(Int.self)
        let height     = try values.decode(Int.self)
        let pixelBytes = try RuntimeArchiveCost.multiply(RuntimeArchiveCost.multiply(width, height), 4)
        _ = try AssetRasterLayout(
            width    : width,
            height   : height,
            byteCount: pixelBytes
        )

        let pixels = try leaf(
            values.superDecoder(),
            maximum: 4_000_000,
            budget : &budget
        )
        try RuntimeArchiveCost.require(pixels.count == pixelBytes)
        try RuntimeArchiveCost.require(values.isAtEnd)

        return Blob(
            id       : id,
            partition: partition,
            width    : width,
            height   : height,
            pixels   : pixels
        )
    }

    /// writeBlob traverses its fixed version 1 row without materializing an input-dependent key collection.
    private static func writeBlob(
        _ value   : Blob,
        to encoder: any Encoder
    ) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(Leaf(bytes: value.id))
        try values.encode(Leaf(bytes: value.partition))
        try values.encode(value.width)
        try values.encode(value.height)
        try values.encode(Leaf(bytes: value.pixels))
    }
}
