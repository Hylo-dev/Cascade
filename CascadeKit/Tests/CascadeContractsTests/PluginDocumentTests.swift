//
//  PluginDocumentTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginDocumentTests {

    @Test
    func roundTripsTheClockAndTheMusicRow() throws {
        for root in [PluginNodeFixtures.clock(), PluginNodeFixtures.musicRow()] {
            let document = try PluginDocument(root: root)
            let decoded  = try PluginDocument.decode(JSONEncoder().encode(document))

            #expect(decoded == document)
        }
    }

    @Test
    func leavesUndeclaredNodeListsEmpty() throws {
        let json = #"{"schema":2,"root":{"kind":{"spacer":{}}}}"#
        let root = try PluginDocument.decode(Data(json.utf8)).root

        #expect(root.modifiers.isEmpty && root.children.isEmpty && root.layers.isEmpty && root.id == nil)
    }

    @Test(arguments: [
        #"{"schema":2,"root":{"kind":{"marquee":{"_0":"x"}}}}"#,
        #"{"schema":2,"root":{"kind":{"spacer":{}},"modifiers":[{"blur":{"_0":2}}]}}"#,
        #"{"schema":2,"root":{"kind":{"spacer":{}},"style":"plain"}}"#,
        #"{"schema":1,"root":{"kind":{"spacer":{}}}}"#,
    ])
    func rejectsUnknownNodesModifiersFieldsAndSchemas(_ json: String) {
        #expect(throws: (any Error).self) { try PluginDocument.decode(Data(json.utf8)) }
    }

    @Test
    func rejectsOversizedDataBeforeDecoding() {
        let data = Data(repeating: 32, count: PluginDocument.maximumBytes + 1)

        #expect(throws: AddonFailure.self) { try PluginDocument.decode(data) }
    }
}
