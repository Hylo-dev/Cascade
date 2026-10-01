//
//  PluginMessageTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginMessageTests {

    @Test
    func everyEventRoundTripsThroughJSON() throws {
        let events: [PluginEvent] = try [
            .refresh,
            .wake,
            .source(PluginSourceEvent(source: "power", fields: ["charging": .bool(true), "level": .number(0.8)])),
            .action(PluginActionEvent(feature: "now-playing", action: "setVolume", value: .number(0.5))),
        ]

        let decoded = try JSONDecoder().decode([PluginEvent].self, from: JSONEncoder().encode(events))

        #expect(decoded == events)
    }

    @Test
    func aSourceOutsideTheCatalogIsRejected() {
        #expect(throws: AddonFailure.self) {
            try PluginSourceEvent(source: "clock")
        }
    }

    @Test
    func aSourceNumberMustBeFinite() {
        #expect(throws: AddonFailure.self) {
            try PluginSourceEvent(source: "volume", fields: ["level": .number(.nan)])
        }
    }

    @Test
    func aSourceCarriesAtMostThirtyTwoFields() throws {
        let fields = Dictionary(uniqueKeysWithValues: (0..<33).map { index in ("field\(index)", PluginValue.bool(true)) })

        #expect(throws: AddonFailure.self) {
            try PluginSourceEvent(source: "network", fields: fields)
        }
        _ = try PluginSourceEvent(source: "network", fields: fields.filter { $0.key != "field0" })
    }

    @Test
    func anUnknownFieldInASourceEventIsRejected() {
        let data = Data(#"{"source":"power","fields":{},"extra":1}"#.utf8)

        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(PluginSourceEvent.self, from: data)
        }
    }

    @Test
    func aControlNeverSendsText() {
        #expect(throws: AddonFailure.self) {
            try PluginActionEvent(feature: "now-playing", action: "next", value: .string("now"))
        }
    }

    @Test(arguments: [0.5, 86_401])
    func aStaleIntervalStaysBetweenASecondAndADay(_ seconds: Double) {
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "time", surface: .widget, document: nil, staleAfter: seconds)
        }
    }

    @Test
    func anOutputPublishesEachTargetOnce() throws {
        let publication = try PluginPublication(feature: "time", surface: .widget, document: nil)

        #expect(throws: AddonFailure.self) {
            try PluginOutput(publications: [publication, publication])
        }
    }

    @Test
    func anOutputRoundTripsWithItsDocumentAndWake() throws {
        let document = try PluginDocument(root: PluginNodeFixtures.clock())
        let output   = try PluginOutput(
            publications: [PluginPublication(feature: "time", surface: .widget, document: document, staleAfter: 60)],
            wake        : Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(try JSONDecoder().decode(PluginOutput.self, from: JSONEncoder().encode(output)) == output)
    }

    @Test
    func surfacesDeclareOnlyTheKindsTheyHave() throws {
        let surfaces = try PluginSurfaces(activity: PluginPlainSurface())

        #expect(surfaces.declares(.activity))
        #expect(!surfaces.declares(.widget))
        #expect(!surfaces.declares(.notice))
    }
}
