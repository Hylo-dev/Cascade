//
//  RuntimeArchiveCodecTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite
struct RuntimeArchiveCodecTests {

    @Test
    func roundTripsRevisionZeroAndFullTimeline() throws {
        let json        = try publicationJSON()
        let publication = try RuntimeArchivePublicationCodec.decode(json)
        #expect(publication.revision == 0)
        #expect(publication.timeline?.count == 32)

        let footprint = try RuntimeArchivePublicationCodec.inspect(json)
        #expect(footprint.nodes == 32)
        #expect(footprint.documents == 32)
        #expect(footprint.timelineEntries == 32)
        #expect(footprint.requiredBytes > json.count)
        #expect(
            try RuntimeArchivePublicationCodec.decode(RuntimeArchivePublicationCodec.encode(publication))
                == publication
        )
    }

    @Test
    func roundTripsShallowEnvelopeWithTerminalHistory() throws {
        let envelope = try fixture()
        let bytes    = try envelope.encode()
        #expect(bytes.starts(with: Data("bplist00".utf8)))
        #expect(try RuntimeArchiveEnvelope.decode(bytes) == envelope)
    }

    @Test
    func rejectsOversizePublicationBeforeParsing() {
        #expect(throws: AddonFailure.self) {
            try RuntimeArchivePublicationCodec.decode(Data(repeating: 0, count: 266_241))
        }
    }

    @Test(arguments: [
        "schema", "extra", "uuid", "utf8", "duplicate", "notice", "leafLength", "oversizeCount",
    ])
    func rejectsCorruptShallowMetadata(_ corruption: String) throws {
        var object  = try plistObject(fixture().encode())
        var records = try #require(object[4] as? [[Any]])

        switch corruption {
            case "schema": object[0] = 2
            case "extra": object.append(0)
            case "uuid": records[0][0] = [15, Data(0..<15)]
            case "utf8": object[1] = [1, Data([255])]
            case "duplicate": records[1][0] = records[0][0]
            case "notice": records[0][5] = 2
            case "leafLength": object[3] = [1, Data("digest".utf8)]
            case "oversizeCount":
                records = Array(repeating: [], count: 17)
            default: Issue.record("Unrecognized fixture mutation")
        }

        object[4] = records
        #expect(throws: (any Error).self) { try RuntimeArchiveEnvelope.decode(plistData(object)) }
    }

    @Test(arguments: [4, 5])
    func rejectsOversizeTableBeforeDecodingFirstRow(_ table: Int) throws {
        var object    = try plistObject(fixture().encode())
        object[table] = Array(repeating: 0, count: table == 4 ? 17 : 1_639)
        #expect(throws: AddonFailure.self) {
            try RuntimeArchiveEnvelope.decode(plistData(object))
        }
    }

    @Test
    func countsRepeatedBinaryPlistLeafOccurrencesBeforeRetainingThirdRaster() throws {
        var object = try plistObject(fixture().encode())
        let pixels = Data(repeating: 0, count: 4_000_000)
        var blobs: [[Any]] = []

        for index in 0..<3 {
            let identifier = Data(repeating: UInt8(index), count: 16)
            let payload    = index == 0 ? pixels : Data([UInt8(250 + index)])
            let blob: [Any] = [[16, identifier], [], 1000, 1000, [pixels.count, payload]]
            blobs.append(blob)
        }

        object[5]     = blobs
        var records   = try #require(object[4] as? [[Any]])
        records[0][8] = (0..<3).map { index -> [Any] in
            [
                [6, Data("image\(index)".utf8)],
                [
                    16,
                    Data(repeating: UInt8(index), count: 16),
                ],
            ]
        }
        object[4] = records
        let data  = try repeatedRasterReferences(plistData(object))
        #expect(data.count < 8_388_608)
        #expect(throws: AddonFailure.self) { try RuntimeArchiveEnvelope.decode(data) }
    }

    @Test
    func rejectsAggregateLeafGrowthBeforeDecodingPoisonScalar() throws {
        var object = try plistObject(fixture().encode())
        let pixels = Data(repeating: 0, count: 4_000_000)
        var blobs: [[Any]] = []

        for index in 0..<3 {
            let identifier = Data(repeating: UInt8(index), count: 16)
            let payload: Any

            switch index {
                case 0: payload = pixels
                case 1: payload = Data([251])
                default: payload = 7
            }

            blobs.append([[16, identifier], [], 1000, 1000, [pixels.count, payload]])
        }

        object[5]     = blobs
        var records   = try #require(object[4] as? [[Any]])
        records[0][8] = (0..<3).map { index -> [Any] in
            [
                [6, Data("image\(index)".utf8)],
                [
                    16,
                    Data(repeating: UInt8(index), count: 16),
                ],
            ]
        }
        object[4] = records
        let data  = try repeatedRasterReferences(plistData(object), expectedReplacements: 1)
        #expect(data.count < 8_388_608)
        // The first two decoded leaves refer to the same real 4 MB Data object. The third
        // declares another 4 MB but holds an integer: entering Data decoding produces a
        // DecodingError, so only the earlier aggregate guard satisfies this expectation.
        #expect(throws: AddonFailure.self) { try RuntimeArchiveEnvelope.decode(data) }
    }

    @Test(arguments: ["dangling", "partition", "duplicateAlias", "unreferencedBlob", "layout", "overflow"])
    func rejectsInvalidRasterRelationships(_ corruption: String) throws {
        var object     = try plistObject(fixture().encode())
        var records    = try #require(object[4] as? [[Any]])
        let identifier = Data(repeating: 42, count: 16)
        let alias: [Any] = [[5, Data("image".utf8)], [16, identifier]]
        records[0][8] = [alias]
        var blob: [Any] = [
            [16, identifier], [], 1, 1,
            [
                4,
                Data(repeating: 0, count: 4),
            ],
        ]

        switch corruption {
            case "dangling":
                blob[0] = [
                    16,
                    Data(repeating: 43, count: 16),
                ]

            case "partition":
                blob[1] = [
                    16,
                    Data(repeating: 9, count: 16),
                ]

            case "duplicateAlias": records[0][8] = [alias, alias]
            case "unreferencedBlob": records[0][8] = []
            case "layout": blob[2] = 2
            case "overflow": blob[2] = Int.max
            default: Issue.record("Unrecognized fixture mutation")
        }

        object[4] = records
        object[5] = [blob]
        #expect(throws: (any Error).self) { try RuntimeArchiveEnvelope.decode(plistData(object)) }
    }

    @Test
    func countsAliasOccurrencesAcrossPublicationsAndAcceptsMaximumRasterLayout() throws {
        var object     = try plistObject(fixture().encode())
        var records    = try #require(object[4] as? [[Any]])
        let identifier = Data(repeating: 42, count: 16)
        let aliases: [[Any]] = (0..<4_096).map { index in
            let name = Data("asset-\(index)".utf8)
            return [[name.count, name], [16, identifier]]
        }
        records[0][8] = aliases
        records[1][7] = records[0][7]
        records[1][8] = aliases
        object[4]     = records
        let pixels    = Data(repeating: 0, count: 4_000_000)
        object[5]     = [[[16, identifier], [], 1000, 1000, [pixels.count, pixels]]]
        let accepted  = try RuntimeArchiveEnvelope.decode(plistData(object))
        #expect(accepted.records.reduce(0) { $0 + $1.aliases.count } == 8_192)
        #expect(accepted.blobs.first?.pixels.count == 4_000_000)

        var excessive = aliases
        excessive.append([[5, Data("extra".utf8)], [16, identifier]])
        records[1][8] = excessive
        object[4]     = records
        #expect(throws: AddonFailure.self) { try RuntimeArchiveEnvelope.decode(plistData(object)) }
    }

    @Test
    func checksActualEncodedOutputAfterAdmittingValidLeafTotal() throws {
        let base       = try fixture()
        let identifier = Data(repeating: 42, count: 16)
        let second     = Data(repeating: 43, count: 16)
        let aliases    = (0..<1_000).map { index in
            RuntimeArchiveEnvelope.Alias(
                name: Data("asset-\(index)".utf8),
                blob: index == 0 ? second : identifier
            )
        }
        let records = base.records.enumerated().map { index, record in
            RuntimeArchiveEnvelope.Record(
                instance       : record.instance,
                session        : record.session,
                feature        : record.feature,
                partition      : nil,
                revision       : record.revision,
                kind           : record.kind,
                sessionDeadline: record.sessionDeadline,
                publication    : Data(repeating: UInt8(32 + index), count: 180_000),
                aliases        : index == 0 ? aliases : []
            )
        }
        let value = RuntimeArchiveEnvelope(
            publisher: base.publisher,
            addon    : base.addon,
            digest   : base.digest,
            records  : records,
            blobs    : [
                RuntimeArchiveEnvelope.Blob(
                    id       : identifier,
                    partition: nil,
                    width    : 1000,
                    height   : 1000,
                    pixels   : Data(repeating: 0, count: 4_000_000)
                ),
                RuntimeArchiveEnvelope.Blob(
                    id       : second,
                    partition: nil,
                    width    : 1000,
                    height   : 1000,
                    pixels   : Data(repeating: 1, count: 4_000_000)
                ),
            ]
        )
        try value.validate()
        #expect(try value.leafBytes() < 8_388_608)
        #expect(throws: AddonFailure.self) { try value.encode() }
    }

    @Test
    func validatesPublicationIdentityRevisionAndExactDeclaredAliasMap() throws {
        let envelope    = try fixture()
        let record      = try #require(envelope.records.first)
        let publication = try RuntimeArchivePublicationCodec.decode(#require(record.publication))
        try RuntimeArchivePublicationCodec.validateBinding(
            publication,
            record: record,
            owner : publication.id.addonID
        )

        let foreign = try #require(AddonID(rawValue: "com.example.foreign"))
        #expect(throws: AddonFailure.self) {
            try RuntimeArchivePublicationCodec.validateBinding(
                publication,
                record: record,
                owner : foreign
            )
        }

        let other = RuntimeArchiveEnvelope.Record(
            instance       : record.instance,
            session        : record.session,
            feature        : record.feature,
            partition      : nil,
            revision       : 1,
            kind           : record.kind,
            sessionDeadline: record.sessionDeadline,
            publication    : record.publication,
            aliases        : []
        )
        #expect(throws: AddonFailure.self) {
            try RuntimeArchivePublicationCodec.validateBinding(
                publication,
                record: other,
                owner : publication.id.addonID
            )
        }

        let misbound = RuntimeArchiveEnvelope.Record(
            instance       : record.instance,
            session        : record.session,
            feature        : record.feature,
            partition      : nil,
            revision       : record.revision,
            kind           : record.kind,
            sessionDeadline: record.sessionDeadline,
            publication    : record.publication,
            aliases        : [RuntimeArchiveEnvelope.Alias(
                name: Data("undeclared".utf8),
                blob: record.instance
            )]
        )
        #expect(throws: AddonFailure.self) {
            try RuntimeArchivePublicationCodec.validateBinding(
                publication,
                record: misbound,
                owner : publication.id.addonID
            )
        }
    }

    @Test
    func derivesCheckedChargesAndRejectsOverflow() throws {
        #expect(
            try RuntimeArchiveEnvelope.metadataBytes(
                records: 3,
                aliases: 4,
                blobs  : 2
            ) == 83_968
        )
        #expect(
            try RuntimeArchivePublicationCodec.charge(
                nodes          : 0,
                assets         : 0,
                documents      : 0,
                lights         : 0,
                timelineEntries: 0,
                jsonBytes      : 0
            ) == 65_536
        )
        #expect(try RuntimeArchivePublicationCodec.inspectionReservationBytes() > 32 * 1_024 * 1_024)
        #expect(throws: AddonFailure.self) {
            try RuntimeArchivePublicationCodec.charge(
                nodes          : Int.max,
                assets         : 0,
                documents      : 0,
                lights         : 0,
                timelineEntries: 0,
                jsonBytes      : 0
            )
        }
        #expect(throws: AddonFailure.self) {
            try RuntimeArchiveEnvelope.metadataBytes(
                records: 0,
                aliases: -1,
                blobs  : 0
            )
        }
        #expect(throws: AddonFailure.self) {
            try RuntimeArchiveCost.add(Int.max, 1)
        }
    }

    /// repeatedRasterReferences changes only array reference slots in a Foundation-produced plist.
    /// It is a fixture mutator, not an archive parser: unused one-byte placeholders remain in place.
    private func repeatedRasterReferences(
        _ input             : Data,
        expectedReplacements: Int = 2
    ) throws -> Data {
        var bytes = Array(input)

        func integer(
            _ start: Int,
            _ size : Int
        ) -> Int {
            (start..<(start + size)).reduce(0) { ($0 << 8) | Int(bytes[$1]) }
        }

        let trailer       = bytes.count - 32
        let offsetSize    = Int(bytes[trailer + 6])
        let referenceSize = Int(bytes[trailer + 7])
        let count         = integer(trailer + 8, 8)
        let offsetTable   = integer(trailer + 24, 8)
        let offsets       = (0..<count).map {
            integer(offsetTable + $0 * offsetSize, offsetSize)
        }

        func layout(_ offset: Int) -> (
            count: Int,
            start: Int
        ) {
            let nibble = Int(bytes[offset] & 15)
            if nibble < 15 { return (nibble, offset + 1) }

            let width = 1 << Int(bytes[offset + 1] & 15)
            return (integer(offset + 2, width), offset + 2 + width)
        }

        let pixelID = try #require(
            offsets.indices.first { index in
                bytes[offsets[index]] >> 4 == 4 && layout(offsets[index]).count == 4_000_000
            }
        )
        let placeholders = Set(
            offsets.indices.filter { index in
                let offset = offsets[index]
                return bytes[offset] == 0x41 && (bytes[offset + 1] == 251 || bytes[offset + 1] == 252)
            }
        )
        #expect(placeholders.count == expectedReplacements)

        var replacements = 0

        for offset in offsets where bytes[offset] >> 4 == 10 {
            let array = layout(offset)

            for element in 0..<array.count {
                let position = array.start + element * referenceSize
                guard placeholders.contains(integer(position, referenceSize)) else { continue }

                for byte in 0..<referenceSize {
                    bytes[position + byte] = UInt8((pixelID >> ((referenceSize - byte - 1) * 8)) & 255)
                }

                replacements += 1
            }
        }

        #expect(replacements == expectedReplacements)
        return Data(bytes)
    }

    private func plistObject(_ data: Data) throws -> [Any] {
        try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [Any])
    }

    private func plistData(_ object: [Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: object,
            format          : .binary,
            options         : 0
        )
    }

    private func publicationJSON() throws -> Data {
        let document: [String: Any] = [
            "schemaVersion": 1,
            "root": ["kind": "text", "text": "Later"],
            "accessibilityLabel": "Later",
            "privacy": "public",
            "assets": [],
        ]
        let object: [String: Any] = [
            "id": [
                "addonID": "com.example.archive", "instanceID": uuid.uuidString, "sessionID": uuid.uuidString,
            ],
            "revision": 0,
            "kind": "widget",
            "timeline": (0..<32).map { ["date": $0, "content": ["widget": document]] as [String: Any] },
            "expiresAt": 1000,
            "stalePolicy": "remove",
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private var uuid: UUID { UUID(uuid: (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)) }

    private func fixture() throws -> RuntimeArchiveEnvelope {
        RuntimeArchiveEnvelope(
            publisher: Data("publisher".utf8),
            addon    : Data("com.example.archive".utf8),
            digest   : Data("digest".utf8),
            records  : [
                RuntimeArchiveEnvelope.Record(
                    instance       : Data(0..<16),
                    session        : Data(0..<16),
                    feature        : Data("feature".utf8),
                    partition      : nil,
                    revision       : 0,
                    kind           : .widget,
                    sessionDeadline: Date(timeIntervalSinceReferenceDate: 1000),
                    publication    : try publicationJSON(),
                    aliases        : []
                ),
                RuntimeArchiveEnvelope.Record(
                    instance       : Data(16..<32),
                    session        : Data(0..<16),
                    feature        : Data("feature".utf8),
                    partition      : nil,
                    revision       : UInt64.max,
                    kind           : .activity,
                    sessionDeadline: Date(timeIntervalSinceReferenceDate: 900),
                    publication    : nil,
                    aliases        : []
                ),
            ],
            blobs    : []
        )
    }
}
