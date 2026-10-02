//
//  BatteryPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct BatteryPluginTests {

    private let context = PluginContext(plugin: BatteryPlugin.id)

    private func power(
        _ percentage: Int?,
        external    : Bool = false,
        charging    : Bool = false,
        lowPower    : Bool = false
    ) throws -> PluginEvent {
        .source(try PluginPowerState(percentage: percentage, isExternalPower: external, isCharging: charging, isLowPowerMode: lowPower).event())
    }

    /// texts collects every text node of a face, depth first, so a test can read what it says.
    /// large is a face's largest variant, the one a 2x2 tile shows.
    private func large(_ publication: PluginPublication) throws -> PluginNode {
        let document = try #require(publication.document)

        return try #require(document.root.children.first)
    }

    private func texts(in node: PluginNode) -> [String] {
        var found: [String] = []
        if case .text(let text) = node.kind {
            found.append(text)
        }
        for child in node.children + node.layers {
            found += texts(in: child)
        }

        return found
    }

    @Test
    func theFirstStatePublishesTheWidgetAndAsksForNoWake() throws {
        let plugin = BatteryPlugin()

        let output      = try plugin.handle(try power(82), context: context)
        let publication = try #require(output.publications.first)

        #expect(output.publications.count == 1)
        #expect(output.wake == nil)
        #expect(publication.feature == BatteryPlugin.feature)
        #expect(publication.surface == .widget)
        #expect(publication.document?.componentReferences == [try PluginComponentReference(id: "power.battery", version: 1)])
    }

    @Test
    func anUnchangedStateIsNotPublishedAgain() throws {
        let plugin = BatteryPlugin()
        _ = try plugin.handle(try power(82), context: context)

        let repeated = try plugin.handle(try power(82), context: context)
        let changed  = try plugin.handle(try power(81), context: context)

        #expect(repeated.publications.isEmpty)
        #expect(changed.publications.count == 1)
    }

    @Test
    func aRefreshRepublishesTheLastStateAndNothingBeforeOne() throws {
        let plugin = BatteryPlugin()

        let early = try plugin.handle(.refresh, context: context)
        _ = try plugin.handle(try power(40, external: true, charging: true), context: context)
        let refreshed = try plugin.handle(.refresh, context: context)

        #expect(early.publications.isEmpty)
        #expect(refreshed.publications == [try BatteryFace.publication(for: PluginPowerState(percentage: 40, isExternalPower: true, isCharging: true, isLowPowerMode: false))])
    }

    @Test
    func theFaceShowsThePercentageAndTheStatus() throws {
        let charging = try BatteryFace.publication(for: PluginPowerState(percentage: 40, isExternalPower: true, isCharging: true, isLowPowerMode: false))
        let battery  = try BatteryFace.publication(for: PluginPowerState(percentage: 82, isExternalPower: false, isCharging: false, isLowPowerMode: false))
        let lowPower = try BatteryFace.publication(for: PluginPowerState(percentage: 12, isExternalPower: false, isCharging: false, isLowPowerMode: true))
        let held     = try BatteryFace.publication(for: PluginPowerState(percentage: 80, isExternalPower: true, isCharging: false, isLowPowerMode: false))

        #expect(texts(in: try large(charging)) == ["Charging", "40%"])
        #expect(texts(in: try large(battery)) == ["On Battery", "82%"])
        #expect(texts(in: try large(lowPower)) == ["Low Power Mode", "12%"])
        #expect(texts(in: try large(held)) == ["Plugged In", "80%"])
    }

    @Test
    func anUnknownChargeReadsAsADash() throws {
        let unknown = try BatteryFace.publication(for: PluginPowerState(percentage: nil, isExternalPower: false, isCharging: false, isLowPowerMode: false))

        #expect(texts(in: try large(unknown)).last == "—")
    }

    @Test
    func theManifestDeclaresBothSizesThePowerSourceAndTheBattery() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == BatteryPlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "BatteryPlugin")
        #expect(feature.id == BatteryPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == [try PluginWidgetSize(columns: 2, rows: 1), try PluginWidgetSize(columns: 2, rows: 2), try PluginWidgetSize(columns: 1, rows: 1)])
        #expect(feature.sources == [PluginPowerState.source])
        #expect(feature.components == [try PluginComponentReference(id: "power.battery", version: 1)])
    }

    /// battery finds the kernel-drawn battery's parameters in a face.
    private func battery(in node: PluginNode) -> [String: PluginValue]? {
        if case .component("power.battery", _, let parameters) = node.kind { return parameters }

        return node.children.lazy.compactMap { battery(in: $0) }.first
    }

    @Test
    func theChargeHasAWholeRowSoAFullBatteryFits() throws {
        let full   = try BatteryFace.publication(for: PluginPowerState(percentage: 100, isExternalPower: true, isCharging: true, isLowPowerMode: false))
        let root   = try large(full)
        let charge = try #require(root.children.last)

        #expect(charge.kind == .text("100%"))
        #expect(!root.children.contains { row in row.children.contains { $0.kind == .spacer(minLength: 0) } })
    }

    @Test
    func aChargingBatteryCarriesItsBolt() throws {
        let charging = try BatteryFace.publication(for: PluginPowerState(percentage: 40, isExternalPower: true, isCharging: true, isLowPowerMode: false))
        let held     = try BatteryFace.publication(for: PluginPowerState(percentage: 80, isExternalPower: true, isCharging: false, isLowPowerMode: false))

        #expect(battery(in: try #require(charging.document).root)?["isCharging"] == .bool(true))
        #expect(battery(in: try #require(held.document).root)?["isCharging"] == .bool(false))
    }

    @Test
    func theFaceComesInALargeAMediumAndASmallVariant() throws {
        let face  = try #require(try BatteryFace.publication(for: PluginPowerState(percentage: 100, isExternalPower: true, isCharging: true, isLowPowerMode: false)).document).root
        let short = try #require(face.children.last)

        #expect(face.kind == .viewThatFits(axes: .vertical))
        #expect(face.children.count == 2)
        #expect(short.kind == .viewThatFits(axes: .horizontal))
        #expect(short.children.count == 2)
        #expect(texts(in: try #require(short.children.first)) == ["100%"])
        #expect(battery(in: try #require(short.children.first))?["isCharging"] == .bool(true))
    }

    /// ViewThatFits measures a face with the tile's other side already given, so shrinking text
    /// would let the large face pass for a small tile; fixed thresholds keep the choice on the tile.
    @Test
    func eachFaceIsChosenByItsTileNotByHowFarItsTextShrinks() throws {
        let face   = try #require(try BatteryFace.publication(for: PluginPowerState(percentage: 50, isExternalPower: false, isCharging: false, isLowPowerMode: false)).document).root
        let large  = try #require(face.children.first)
        let medium = try #require(face.children.last?.children.first)

        #expect(large.modifiers.contains(.frame(width: nil, height: BatteryFace.largeHeight, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)))
        #expect(medium.modifiers.contains(.frame(width: BatteryFace.mediumWidth, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)))
    }

    @Test
    func theSmallFaceIsTheBatteryWithItsChargeInsideAndABoltWhileCharging() throws {
        let charging = try #require(try BatteryFace.publication(for: PluginPowerState(percentage: 64, isExternalPower: true, isCharging: true, isLowPowerMode: false)).document).root
        let onBattery = try #require(try BatteryFace.publication(for: PluginPowerState(percentage: 64, isExternalPower: false, isCharging: false, isLowPowerMode: false)).document).root
        let small    = try #require(charging.children.last?.children.last)
        let quiet    = try #require(onBattery.children.last?.children.last)

        #expect(battery(in: small)?["showsPercentage"] == .bool(true))
        #expect(texts(in: small).isEmpty)
        #expect(small.children.contains { $0.kind == .symbol(name: "bolt.fill") })
        #expect(!quiet.children.contains { $0.kind == .symbol(name: "bolt.fill") })
    }
}
