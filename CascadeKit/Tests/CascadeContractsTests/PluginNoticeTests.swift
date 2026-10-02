//
//  PluginNoticeTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginNoticeTests {

    private func regions(_ count: Int = 3) -> PluginNode {
        PluginNode(.regions, children: (0..<count).map { PluginNode(.text("\($0)")) })
    }

    private func attributes() throws -> PluginNoticeAttributes {
        try PluginNoticeAttributes(duration: 4, border: .charging, compactWidth: 116, accessibilityLabel: "Charging, 80 percent")
    }

    @Test
    func aNoticeRoundTripsWithItsRegionsAndAttributes() throws {
        let notice = try PluginPublication(feature: "charging", surface: .notice, document: PluginDocument(root: regions()), notice: attributes())

        let decoded = try JSONDecoder().decode(PluginPublication.self, from: JSONEncoder().encode(notice))

        #expect(decoded == notice)
        #expect(decoded.notice?.border == .charging)
    }

    @Test
    func regionsAreOnlyANoticeOrActivityRoot() throws {
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "time", surface: .widget, document: PluginDocument(root: regions()))
        }
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: PluginNode(.vStack(alignment: .center, spacing: nil), children: [regions()]))
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "charging", surface: .notice, document: PluginDocument(root: PluginNode(.text("Charging"))), notice: attributes())
        }
    }

    @Test
    func noticesKeepThreeRegionsWhileActivitiesCanExpand() throws {
        #expect(throws: AddonFailure.self) {
            try PluginDocument(root: regions(2))
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "charging", surface: .notice, document: PluginDocument(root: regions(4)), notice: attributes())
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "recording", surface: .activity, document: PluginDocument(root: regions()))
        }
        let activity = try PluginPublication(feature: "recording", surface: .activity, document: PluginDocument(root: regions(4)))
        #expect(try JSONDecoder().decode(PluginPublication.self, from: JSONEncoder().encode(activity)) == activity)
    }

    @Test
    func aNoticeCarriesItsAttributesAndOnlyANoticeDoes() throws {
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "charging", surface: .notice, document: PluginDocument(root: regions()))
        }
        #expect(throws: AddonFailure.self) {
            try PluginPublication(feature: "time", surface: .widget, document: PluginDocument(root: PluginNode(.clock)), notice: attributes())
        }
        _ = try PluginPublication(feature: "charging", surface: .notice, document: nil)
    }

    @Test(arguments: [
        (0.5, nil, "Label"),
        (11.0, nil, "Label"),
        (4.0, 10.0, "Label"),
        (4.0, 500.0, "Label"),
        (4.0, nil, ""),
    ] as [(Double, Double?, String)])
    func noticeAttributesStayInBounds(_ duration: Double, _ width: Double?, _ label: String) {
        #expect(throws: AddonFailure.self) {
            try PluginNoticeAttributes(duration: duration, border: nil, compactWidth: width, accessibilityLabel: label)
        }
    }

    @Test
    func aNoticeShowsUnlessItAsksOnlyToUpdate() throws {
        let shown   = try PluginNoticeAttributes(duration: 4, accessibilityLabel: "Notice")
        let updated = try PluginNoticeAttributes(duration: 4, accessibilityLabel: "Notice", delivery: .update)
        let legacy  = try JSONDecoder().decode(PluginNoticeAttributes.self, from: Data(#"{"duration":4,"accessibilityLabel":"Notice"}"#.utf8))

        #expect(shown.delivery == .show)
        #expect(legacy.delivery == .show)
        #expect(try JSONDecoder().decode(PluginNoticeAttributes.self, from: JSONEncoder().encode(updated)) == updated)
    }
}
