//
//  ContentValidationTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import Foundation
import Testing

@Suite
struct ContentValidationTests {
    @Test
    func rejectsImageWithoutAccessibleLabel() {
        #expect(throws: (any Error).self) {
            try ContentNode(
                kind: .image,
                text: nil,
                assetID: "cover",
                value: nil,
                deadline: nil,
                actionID: nil,
                children: nil
            )
        }
    }
    @Test
    func rejectsEmptyButtonLabel() {
        #expect(throws: (any Error).self) {
            try ContentNode(
                kind: .action,
                text: "",
                assetID: nil,
                value: nil,
                deadline: nil,
                actionID: "go",
                children: nil
            )
        }
    }
    @Test
    func rejectsURLAsSymbol() {
        #expect(throws: (any Error).self) {
            try ContentNode(
                kind: .symbol,
                text: "https://example.com/icon",
                assetID: nil,
                value: nil,
                deadline: nil,
                actionID: nil,
                children: nil
            )
        }
    }

    @Test
    func rejectsTreeBeyondDepthAndNodeLimits() throws {
        var node = try ContentNode.text("leaf")
        for _ in 1..<8 { node = try .column([node]) }
        #expect(throws: (any Error).self) { try ContentNode.row([node]) }
        let leaves = try (0..<128).map { _ in try ContentNode.text("x") }
        #expect(throws: (any Error).self) { try ContentNode.row(leaves) }
        #expect(try ContentNode.row(Array(leaves.prefix(127))).children?.count == 127)
    }

    @Test
    func clampsFiniteProgressAndRejectsNonfinite() throws {
        #expect(try CascadeProgress(value: -1).contentNode.value == 0)
        #expect(try CascadeProgress(value: 2).contentNode.value == 1)
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try CascadeProgress(value: value) }
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ContentNode.self, from: Data(#"{"kind":"progress","value":2}"#.utf8))
        }
    }

    @Test
    func enforcesStringsAssetsActionsAndWireBudget() throws {
        #expect(throws: (any Error).self) { try CascadeText(String(repeating: "é", count: 2049)) }
        let image = try CascadeImage(assetID: "cover", accessibilityLabel: "Cover")
        #expect(throws: (any Error).self) {
            try ContentDocument(root: image.contentNode, privacy: .publicContent, accessibilityLabel: "Image")
        }
        #expect(throws: (any Error).self) {
            try ContentDocument(
                root: image.contentNode,
                privacy: .publicContent,
                accessibilityLabel: "Image",
                assetIDs: (0..<65).map { "asset\($0)" }
            )
        }
        let action = try CascadeButton(ActionDescriptor(id: "go", label: "Go"))
        #expect(throws: (any Error).self) {
            try ContentDocument(
                root: .row([action.contentNode, action.contentNode]),
                privacy: .publicContent,
                accessibilityLabel: "Actions"
            )
        }
        let text = try CascadeText(String(repeating: "x", count: 4096))
        #expect(throws: (any Error).self) {
            try ContentDocument(
                root: .column(Array(repeating: text.contentNode, count: 16)),
                privacy: .publicContent,
                accessibilityLabel: "Too large"
            )
        }
        #expect(throws: (any Error).self) { try ContentDocument.decode(Data(repeating: 32, count: 65537)) }
        #expect(throws: (any Error).self) {
            try ActionDescriptor(id: "go", label: "Go", payload: Data(repeating: 0, count: 4097))
        }
    }

    @Test
    func rejectsUnknownSchemaAndCrossModeFields() throws {
        #expect(throws: (any Error).self) {
            try ContentDocument(
                schemaVersion: 4,
                root: .text("x"),
                privacy: .publicContent,
                accessibilityLabel: "x"
            )
        }
        for json in [
            #"{"kind":"text","text":"hello","clockFormat":"hourMinute"}"#,
            #"{"kind":"text","text":"hello","actionPayload":""}"#,
            #"{"kind":"text","text":"hello","accessibilityLabel":"Hello"}"#,
            #"{"kind":"clock","clockFormat":"arbitrary-format"}"#,
            #"{"kind":"image","assetID":"https://example.com/a","accessibilityLabel":"Image"}"#,
            #"{"kind":"text","text":"hello","unknown":true}"#,
        ] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(ContentNode.self, from: Data(json.utf8))
            }
        }
    }

    @Test func rejectsDepthNineDuringWireDecoding() throws {
        var node: [String: Any] = ["kind": "text", "text": "leaf"]
        for _ in 1..<9 { node = ["kind": "column", "children": [node]] }
        let data = try JSONSerialization.data(withJSONObject: node)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ContentNode.self, from: data) }
    }
}
