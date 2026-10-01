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

    @Test
    func acceptsTheNodeBudgetExactlyAndRejectsOneMore() throws {
        let largest = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes - 1)
        let tooMany = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes)

        #expect(throws: Never.self) { try PluginDocument(root: largest) }
        #expect(throws: AddonFailure.self) { try PluginDocument(root: tooMany) }
    }

    @Test
    func layersCountTowardTheNodeBudget() throws {
        let full    = PluginNodeFixtures.stack(of: PluginDocument.maximumNodes - 1)
        let layered = PluginNode(full.kind, modifiers: [.overlay(alignment: .center)], children: full.children, layers: [PluginNode(.text("badge"))])

        #expect(throws: AddonFailure.self) { try PluginDocument(root: layered) }
    }

    @Test
    func acceptsTheDepthLimitExactlyAndRejectsOneMore() throws {
        #expect(throws: Never.self) { try PluginDocument(root: PluginNodeFixtures.nested(depth: PluginDocument.maximumDepth)) }
        #expect(throws: AddonFailure.self) { try PluginDocument(root: PluginNodeFixtures.nested(depth: PluginDocument.maximumDepth + 1)) }
    }

    @Test
    func rejectsDocumentsPastSixtyFourKibibytes() {
        let text = String(repeating: "a", count: 4_000)
        let root = PluginNode(.vStack(alignment: .center, spacing: nil), children: Array(repeating: PluginNode(.text(text)), count: 17))

        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test
    func rejectsDuplicateExplicitIDs() {
        let root = PluginNode(
            .hStack(alignment: .center, spacing: nil),
            children: [PluginNode(.text("a"), id: "title"), PluginNode(.text("b"), id: "title")]
        )

        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.text("leaf"), children: [PluginNode(.text("child"))]),
        PluginNode(.spacer(minLength: nil), modifiers: [.overlay(alignment: .center)]),
        PluginNode(.spacer(minLength: nil), layers: [PluginNode(.text("orphan"))]),
    ])
    func rejectsStructureThatCannotRender(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.spacer(minLength: nil), modifiers: [.opacity(.nan)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.frame(width: .infinity, height: nil, maxWidth: nil, maxHeight: nil, alignment: .center)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.frame(width: nil, height: nil, maxWidth: .points(.nan), maxHeight: nil, alignment: .center)]),
        PluginNode(.date(Date(timeIntervalSinceReferenceDate: .infinity), style: .time)),
        PluginNode(.progress(value: .nan, total: 1, style: .linear)),
        PluginNode(.spacer(minLength: nil), modifiers: [.foregroundStyle(.color(PluginColor(red: .infinity, green: 0, blue: 0)))]),
    ])
    func rejectsNonFiniteNumbers(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.progress(value: 2, total: 1, style: .circular)),
        PluginNode(.slider(value: 5, minimum: 0, maximum: 1, step: nil, action: "volume")),
        PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: 0, action: "volume")),
        PluginNode(.timer(start: PluginNodeFixtures.now, end: PluginNodeFixtures.now - 1, countsDown: true)),
        PluginNode(.spacer(minLength: nil), modifiers: [.opacity(1.5)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.lineLimit(0)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.minimumScaleFactor(0)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.padding(.all, length: -1)]),
        PluginNode(.spacer(minLength: nil), modifiers: [.transition(.move(.horizontal))]),
        PluginNode(.spacer(minLength: nil), modifiers: [.foregroundStyle(.gradient([.white]))]),
        PluginNode(.text("x"), modifiers: [.font(PluginFont(style: .body, size: 12))]),
        PluginNode(.text("x"), modifiers: [.font(PluginFont())]),
        PluginNode(.shape(.roundedRectangle(cornerRadius: -2))),
    ])
    func rejectsValuesOutOfRange(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test(arguments: [
        PluginNode(.button(action: "skip forward")),
        PluginNode(.symbol(name: "")),
        PluginNode(.asset(id: "art work")),
        PluginNode(.text("x"), id: "has space"),
        PluginNode(.component(id: "audio.spectrum", version: 0, parameters: [:])),
        PluginNode(.component(id: "audio.spectrum", version: 1, parameters: ["bad key": .bool(true)])),
    ])
    func rejectsMalformedIdentifiers(_ root: PluginNode) {
        #expect(throws: AddonFailure.self) { try PluginDocument(root: root) }
    }

    @Test
    func rejectsMoreGlassLightsThanTheRendererDraws() throws {
        let light  = try GlassLight(x: 0.5, y: 0.5, radius: 0.2, red: 1, green: 1, blue: 1, intensity: 0.5)
        let lights = Array(repeating: light, count: GlassLight.maximumCount + 1)

        #expect(throws: AddonFailure.self) { try PluginDocument(root: PluginNodeFixtures.clock(), glassLights: lights) }
    }

    @Test
    func listsTheComponentsADocumentShows() throws {
        let root = PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: [
                PluginNode(.component(id: "audio.spectrum", version: 1, parameters: ["bars": .number(12)])),
                PluginNode(.text("x"), layers: []),
            ],
            layers: []
        )
        let document = try PluginDocument(root: root)
        let spectrum = try PluginComponentReference(id: "audio.spectrum", version: 1)

        #expect(document.componentReferences == [spectrum])
    }

    @Test
    func rejectsADeepDocumentWhileDecodingWithoutExhaustingTheStack() {
        let levels = 200
        let node   = String(repeating: #"{"kind":{"vStack":{"alignment":"center"}},"children":["#, count: levels)
            + #"{"kind":{"spacer":{}}}"#
            + String(repeating: "]}", count: levels)
        let data   = Data((#"{"schema":2,"root":"# + node + "}").utf8)

        let rejected = onSmallStack {
            do {
                _ = try PluginDocument.decode(data)
                return false
            } catch {
                return error is AddonFailure
            }
        }

        #expect(rejected)
    }
}
