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

        #expect(texts(in: try #require(charging.document).root) == ["Charging", "40%"])
        #expect(texts(in: try #require(battery.document).root) == ["On Battery", "82%"])
        #expect(texts(in: try #require(lowPower.document).root) == ["Low Power", "12%"])
        #expect(texts(in: try #require(held.document).root) == ["Plugged In", "80%"])
    }

    @Test
    func anUnknownChargeReadsAsADash() throws {
        let unknown = try BatteryFace.publication(for: PluginPowerState(percentage: nil, isExternalPower: false, isCharging: false, isLowPowerMode: false))

        #expect(texts(in: try #require(unknown.document).root).last == "—")
    }

    @Test
    func theManifestDeclaresBothSizesThePowerSourceAndTheBattery() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == BatteryPlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "BatteryPlugin")
        #expect(feature.id == BatteryPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == [try PluginWidgetSize(columns: 2, rows: 1), try PluginWidgetSize(columns: 2, rows: 2)])
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
        let root   = try #require(full.document).root
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
}
