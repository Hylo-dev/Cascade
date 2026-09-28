//
//  BoundedArchiveContractTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite struct BoundedArchiveContractTests {
    @Test func rejectsOversizedChildrenBeforeDecodingTheirFields() throws {
        let object: [String: Any] = [
            "kind": "row",
            "children": Array(
                repeating: [:],
                count    : 128
            ),
        ]
        try expectBudgetFailure(
            object,
            as: ContentNode.self
        )
    }

    @Test func rejectsNinthLevelBeforeDecodingItsFields() throws {
        var object: [String: Any] = [:]
        for _ in 0..<8 { object = ["kind": "row", "children": [object]] }
        try expectBudgetFailure(
            object,
            as: ContentNode.self
        )
    }

    @Test func rejectsOversizedTimelineBeforeDecodingEntries() throws {
        var object = publicationObject()
        object.removeValue(forKey: "content")
        object["timeline"] = Array(
            repeating: [:],
            count    : 33
        )
        try expectBudgetFailure(
            object,
            as: Publication.self
        )
    }

    @Test(arguments: ["assets", "glassLights"])
    func rejectsOversizedDocumentCollectionsBeforeElements(_ field: String) throws {
        var object = documentObject()
        object["schemaVersion"] = 2
        object[field] = Array(
            repeating: NSNull(),
            count    : field == "assets" ? 65 : 9
        )
        try expectBudgetFailure(
            object,
            as: ContentDocument.self
        )
    }

    @Test func rejectsTwoGraphBranchesBeforeDecodingEither() throws {
        var object = publicationObject()
        object["content"] = ["unknownRepresentation": true]
        object["timeline"] = []
        let data = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(
                Publication.self,
                from: data
            )
            Issue.record("Both graph branches must be rejected")
        } catch let failure as AddonFailure {
            #expect(failure.reason == "Publication requires content or timeline exclusively")
        }
    }

    @Test func sharesRemainingNodesAcrossSiblingSubtrees() throws {
        let leaf  : [String: Any] = ["kind": "text", "text": "Leaf"]
        let object: [String: Any] = [
            "kind": "row",
            "children": [
                [
                    "kind": "row",
                    "children": Array(
                        repeating: leaf,
                        count    : 64
                    ),
                ],
                [
                    "kind": "row",
                    "children": Array(
                        repeating: [:],
                        count    : 62
                    ),
                ],
            ],
        ]
        try expectBudgetFailure(
            object,
            as: ContentNode.self
        )
    }

    @Test func acceptsExistingTreeAssetsAndLightBoundaries() throws {
        let leaf: [String: Any] = ["kind": "text", "text": "Leaf"]
        let root: [String: Any] = [
            "kind": "row",
            "children": Array(
                repeating: leaf,
                count    : 127
            ),
        ]
        var document = documentObject()
        document["root"] = root
        document["schemaVersion"] = 2
        document["assets"] = (0..<64).map { "asset-\($0)" }
        document["glassLights"] = Array(
            repeating: [
                "x": 0.5, "y": 0.5, "radius": 0.5, "red": 1.0, "green": 0.0, "blue": 0.0, "intensity": 0.5,
            ],
            count: 8
        )
        let decoded = try ContentDocument.decode(JSONSerialization.data(withJSONObject: document))
        #expect(decoded.root.children?.count == 127)
        #expect(decoded.assets.count == 64)
        #expect(decoded.glassLights?.count == 8)
        var deepest = leaf
        for _ in 0..<7 { deepest = ["kind": "row", "children": [deepest]] }
        _ = try JSONDecoder().decode(
            ContentNode.self,
            from: JSONSerialization.data(withJSONObject: deepest)
        )
    }

    @Test func acceptsExplicitNullAlternativeAndPreservesUnknownFieldRejection() throws {
        var object = publicationObject()
        object["timeline"] = NSNull()
        let valid = try JSONDecoder().decode(
            Publication.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(valid.content != nil && valid.timeline == nil)
        object["future"] = true
        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(
                Publication.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test func supportsUnknownUnkeyedCountWithoutLosingBounds() throws {
        let small = try JSONDecoder().decode(
            CountlessProbe.self,
            from: Data("[1,2,3]".utf8)
        )
        #expect(small.values == [1, 2, 3])
        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(
                CountlessProbe.self,
                from: Data("[1,2,3,{}]".utf8)
            )
        }
    }

    private func expectBudgetFailure<Value: Decodable>(
        _ object: [String: Any],
        as type : Value.Type
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(
                type,
                from: data
            )
            Issue.record("Expected bounded traversal to reject the collection")
        } catch let failure as AddonFailure {
            #expect(failure.code == .invalidPayload)
        } catch {
            Issue.record("Element parsing ran before the structural guard: \(error)")
        }
    }
}

/// CountlessProbe forwards actual Foundation values while exercising the generic unknown-count path.
private struct CountlessProbe: Decodable {
    let values: [Int]
    init(from decoder: any Decoder) throws {
        values = try BoundedContractArray.decode(
            Int.self,
            from   : CountlessDecoder(base: decoder),
            maximum: 3
        )
    }
}

private struct CountlessDecoder: Decoder {
    let base      : any Decoder
    var codingPath: [any CodingKey] { base.codingPath }
    var userInfo  : [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        try base.container(keyedBy: type)
    }
    func singleValueContainer() throws -> any SingleValueDecodingContainer { try base.singleValueContainer() }
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try CountlessContainer(base: base.unkeyedContainer())
    }
}

private struct CountlessContainer: UnkeyedDecodingContainer {
    var base        : any UnkeyedDecodingContainer
    var codingPath  : [any CodingKey] { base.codingPath }
    var count       : Int? { nil }
    var isAtEnd     : Bool { base.isAtEnd }
    var currentIndex: Int { base.currentIndex }
    mutating func decodeNil() throws -> Bool { try base.decodeNil() }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try base.decode(type) }
    mutating func nestedContainer<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<
        Key
    > {
        try base.nestedContainer(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try base.nestedUnkeyedContainer()
    }
    mutating func superDecoder() throws -> any Decoder { try base.superDecoder() }
}
