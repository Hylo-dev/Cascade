//
//  PluginActivityPublicationTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginActivityPublicationTests {

    private func regions(_ count: Int) -> PluginNode {
        PluginNode(.regions, children: (0..<count).map { PluginNode(.text("\($0)")) })
    }

    private func attributes() throws -> PluginActivityAttributes {
        try PluginActivityAttributes(
            startedAt         : Date(timeIntervalSince1970: 1_800_000_000),
            relevance         : 0.3,
            accessibilityLabel: "Caffeinate is on"
        )
    }

    @Test
    func anActivityNeedsFourRegionsAndAttributes() throws {
        _ = try PluginPublication(
            feature : "caffeinate",
            surface : .activity,
            document: PluginDocument(root: regions(4)),
            activity: attributes()
        )

        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "caffeinate",
                surface : .activity,
                document: PluginDocument(root: regions(3)),
                activity: attributes()
            )
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "caffeinate",
                surface : .activity,
                document: PluginDocument(root: regions(4))
            )
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "caffeinate",
                surface : .activity,
                document: PluginDocument(root: PluginNode(.text("Caffeinate"))),
                activity: attributes()
            )
        }
    }

    @Test
    func attributesOnlyOnActivities() throws {
        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "time",
                surface : .widget,
                document: PluginDocument(root: PluginNode(.clock)),
                activity: attributes()
            )
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "charging",
                surface : .notice,
                document: PluginDocument(root: regions(3)),
                activity: attributes()
            )
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "caffeinate", surface: .activity, document: nil, activity: attributes())
        }
        _ = try PluginPublication(feature: "caffeinate", surface: .activity, document: nil)
    }

    @Test
    func noticesStillTakeThreeRegions() throws {
        let notice = try PluginNoticeAttributes(duration: 4, accessibilityLabel: "Charging")

        _ = try PluginPublication(
            feature : "charging",
            surface : .notice,
            document: PluginDocument(root: regions(3)),
            notice  : notice
        )

        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "charging",
                surface : .notice,
                document: PluginDocument(root: regions(4)),
                notice  : notice
            )
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(
                feature : "caffeinate",
                surface : .activity,
                document: PluginDocument(root: regions(4)),
                notice  : notice
            )
        }
    }

    @Test
    func aDocumentTakesThreeOrFourRegionsOnly() throws {
        _ = try PluginDocument(root: regions(3))
        _ = try PluginDocument(root: regions(4))

        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: regions(2))
        }
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: regions(5))
        }
    }

    @Test(arguments: [
        (1.5, "Label"),
        (-0.1, "Label"),
        (Double.nan, "Label"),
        (0.3, ""),
        (0.3, String(repeating: "a", count: 513)),
    ] as [(Double, String)])
    func attributesValidateRange(_ relevance: Double, _ label: String) {
        #expect(throws: AddonFailure.self) {
            try PluginActivityAttributes(startedAt: Date(timeIntervalSince1970: 0), relevance: relevance, accessibilityLabel: label)
        }
    }

    @Test
    func startedAtMustBeFinite() {
        #expect(throws: AddonFailure.self) {
            try PluginActivityAttributes(startedAt: Date(timeIntervalSince1970: .infinity), relevance: 0.3, accessibilityLabel: "Label")
        }
    }

    @Test
    func theRelevanceBoundsAreAccepted() throws {
        _ = try PluginActivityAttributes(startedAt: Date(timeIntervalSince1970: 0), relevance: 0, accessibilityLabel: "Label")
        _ = try PluginActivityAttributes(startedAt: Date(timeIntervalSince1970: 0), relevance: 1, accessibilityLabel: "Label")
    }

    @Test
    func unknownAttributeKeysAreRejected() {
        let json = #"{"startedAt":0,"relevance":0.3,"accessibilityLabel":"Label","border":"charging"}"#

        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(PluginActivityAttributes.self, from: Data(json.utf8))
        }
    }

    @Test
    func activityRoundTripsThroughJSON() throws {
        let activity = try PluginPublication(
            feature : "caffeinate",
            surface : .activity,
            document: PluginDocument(root: regions(4)),
            activity: attributes()
        )

        let decoded = try JSONDecoder().decode(PluginPublication.self, from: JSONEncoder().encode(activity))

        #expect(decoded == activity)
        #expect(decoded.activity?.relevance == 0.3)
    }
}
