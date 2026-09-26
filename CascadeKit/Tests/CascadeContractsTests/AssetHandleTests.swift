//
//  AssetHandleTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@Suite struct AssetHandleTests {
    private let owner: AddonID
    private let publication: PublicationID

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.assets"))
        publication = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    private func handle(
        id      : String = "asset-image",
        owner   : AddonID? = nil,
        revision: UInt64 = 1,
        width   : Int = 1,
        height  : Int = 1,
        bytes   : Int = 4
    ) throws -> AssetHandle {
        try AssetHandle(
            assetID       : id,
            owner         : owner ?? self.owner,
            publicationID : publication,
            rasterRevision: revision,
            width         : width,
            height        : height,
            byteCount     : bytes
        )
    }

    @Test func validRasterMetadataRoundTripsAtPixelLimit() throws {
        let value = try handle(
            revision: UInt64.max,
            width   : 1_000,
            height  : 1_000,
            bytes   : 4_000_000
        )
        #expect(try AssetHandle.decode(JSONEncoder().encode(value)) == value)
    }

    @Test func initializerRejectsInvalidIdentityRevisionAndRasterBounds() throws {
        for id in ["", "../image", String(repeating: "a", count: 129)] {
            #expect(throws: AddonFailure.self) { try handle(id: id) }
        }
        #expect(throws: AddonFailure.self) { try handle(revision: 0) }
        let other = try #require(AddonID(rawValue: "com.example.other"))
        #expect(throws: AddonFailure.self) { try handle(owner: other) }
        for (width, height, bytes) in [(0, 1, 0), (-1, 1, 4), (1, 0, 0),
            (Int.max, 2, 4), (1, Int.max, 4), (1_001, 1_000, 4_004_000),
            (1, 1, 3), (1, 1, 5), (1, 1, -4)] {
            #expect(throws: AddonFailure.self) {
                try handle(
                    width : width,
                    height: height,
                    bytes : bytes
                )
            }
        }
    }

    @Test func decodingCannotBypassMetadataValidationOrAddFields() throws {
        let encoded = try JSONEncoder().encode(handle())
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (key, value) in [("assetID", "../image" as Any), ("owner", "com.example.other"),
            ("rasterRevision", 0), ("width", 0), ("height", -1), ("byteCount", 8),
            ("unknown", true)] {
            var changed = object
            changed[key] = value
            #expect(throws: (any Error).self) {
                try AssetHandle.decode(JSONSerialization.data(withJSONObject: changed))
            }
        }
        for key in object.keys {
            var changed = object
            changed.removeValue(forKey: key)
            #expect(throws: (any Error).self) {
                try AssetHandle.decode(JSONSerialization.data(withJSONObject: changed))
            }
        }
    }

    @Test func rawByteLimitPrecedesParsingIncludingWhitespace() throws {
        let encoded = try JSONEncoder().encode(handle())
        let full = encoded + Data(repeating: 32, count: 8_192 - encoded.count)
        #expect(try AssetHandle.decode(full) == handle())
        #expect(throws: AddonFailure.self) { try AssetHandle.decode(full + Data([32])) }
    }
}
