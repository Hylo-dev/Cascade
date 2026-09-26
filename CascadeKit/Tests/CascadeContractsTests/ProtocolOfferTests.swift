//
//  ProtocolOfferTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@Suite struct ProtocolOfferTests {
    private let valid = #"{"schemaVersion":1,"major":1,"minimumMinor":0,"maximumMinor":65535,"contentSchemas":[2,1,65535]}"#

    @Test func roundTripPreservesOfferedCapabilities() throws {
        let offer = try ProtocolOffer.decode(Data(valid.utf8))
        #expect(offer.major == 1)
        #expect(offer.maximumMinor == 65_535)
        #expect(offer.contentSchemas == [2, 1, 65_535])
        #expect(try ProtocolOffer.decode(JSONEncoder().encode(offer)) == offer)
    }

    @Test func rejectsMalformedClosedOffers() throws {
        let object = try #require(JSONSerialization.jsonObject(with: Data(valid.utf8)) as? [String: Any])
        let invalid: [(String, Any)] = [
            ("schemaVersion", 2), ("major", 0), ("major", 65_536),
            ("minimumMinor", -1), ("minimumMinor", 65_536),
            ("maximumMinor", -1), ("maximumMinor", 65_536),
            ("contentSchemas", []), ("contentSchemas", [1, 1]),
            ("contentSchemas", [0]), ("contentSchemas", [65_536]),
            ("contentSchemas", Array(1...9)), ("unknown", true),
        ]
        for (key, value) in invalid {
            var changed = object
            changed[key] = value
            let data = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: (any Error).self) { try ProtocolOffer.decode(data) }
        }
        for key in object.keys {
            var missing = object
            missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) {
                try ProtocolOffer.decode(JSONSerialization.data(withJSONObject: missing))
            }
            var null = object
            null[key] = NSNull()
            #expect(throws: (any Error).self) {
                try ProtocolOffer.decode(JSONSerialization.data(withJSONObject: null))
            }
        }
        #expect(throws: (any Error).self) {
            try ProtocolOffer.decode(Data(valid.replacingOccurrences(of: "\"minimumMinor\":0", with: "\"minimumMinor\":10").replacingOccurrences(of: "\"maximumMinor\":65535", with: "\"maximumMinor\":9").utf8))
        }
    }

    @Test func initializerCannotBypassOfferBounds() throws {
        for values in [(0, 0, 0), (65_536, 0, 0), (1, -1, 0), (1, 1, 0), (1, 0, 65_536)] {
            #expect(throws: AddonFailure.self) {
                try ProtocolOffer(major: values.0, minimumMinor: values.1, maximumMinor: values.2, contentSchemas: [1])
            }
        }
        for schemas in [[], [1, 1], [0], [-1], [65_536], Array(1...9)] {
            #expect(throws: AddonFailure.self) {
                try ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 0, contentSchemas: schemas)
            }
        }
        #expect(throws: AddonFailure.self) {
            try ProtocolOffer(schemaVersion: 2, major: 1, minimumMinor: 0, maximumMinor: 0, contentSchemas: [1])
        }
    }

    @Test func rawLimitCountsWhitespaceBeforeDecode() throws {
        let withinLimit = Data((valid + String(repeating: " ", count: 8_192 - valid.utf8.count)).utf8)
        #expect(try ProtocolOffer.decode(withinLimit).contentSchemas == [2, 1, 65_535])
        #expect(throws: AddonFailure.self) { try ProtocolOffer.decode(withinLimit + Data([32])) }
    }
}
