//
//  ChargingPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Testing

@testable import CascadePlugins

@Suite
struct ChargingPluginTests {

    private let context = PluginContext(plugin: ChargingPlugin.id)

    private func power(
        _ percentage   : Int?,
        external       : Bool,
        charging       : Bool,
        lowPower       : Bool = false
    ) throws -> PluginEvent {
        .source(try PluginPowerState(percentage: percentage, isExternalPower: external, isCharging: charging, isLowPowerMode: lowPower).event())
    }

    private func publications(
        _ plugin: ChargingPlugin,
        _ event : PluginEvent
    ) throws -> [PluginPublication] {
        try plugin.handle(event, context: context).publications
    }

    @Test
    func theFirstStateIsASilentBaseline() throws {
        let plugin = ChargingPlugin()

        #expect(try publications(plugin, power(19, external: true, charging: true)).isEmpty)
        #expect(try publications(plugin, power(19, external: true, charging: true)).isEmpty)
    }

    @Test
    func connectingTheChargerShowsTheNotice() throws {
        let plugin = ChargingPlugin()
        _ = try publications(plugin, power(19, external: false, charging: false))

        let shown  = try #require(try publications(plugin, power(19, external: true, charging: true)).first)
        let notice = try #require(shown.notice)

        #expect(shown.surface == .notice)
        #expect(shown.feature == ChargingPlugin.feature)
        #expect(notice.delivery == .show)
        #expect(notice.border == .charging)
        #expect(notice.duration == 4)
        #expect(notice.compactWidth == 116)
        #expect(shown.document?.componentReferences == [try PluginComponentReference(id: "power.battery", version: 1)])
    }

    @Test
    func batteryAndEnergyChangesOnlyUpdate() throws {
        let plugin = ChargingPlugin()
        _ = try publications(plugin, power(19, external: false, charging: false))
        _ = try publications(plugin, power(19, external: true, charging: true))

        let updated = try #require(try publications(plugin, power(20, external: true, charging: true, lowPower: true)).first?.notice)

        #expect(updated.delivery == .update)
        #expect(updated.border == .chargingLowPower)
    }

    @Test
    func unpluggingWithdrawsTheNotice() throws {
        let plugin = ChargingPlugin()
        _ = try publications(plugin, power(19, external: false, charging: false))
        _ = try publications(plugin, power(19, external: true, charging: true))

        let withdrawn = try publications(plugin, power(19, external: false, charging: false))

        #expect(withdrawn == [try PluginPublication(feature: ChargingPlugin.feature, surface: .notice, document: nil)])
    }

    @Test
    func chargingOnHoldStillAnnouncesTheCharger() throws {
        let plugin = ChargingPlugin()
        _ = try publications(plugin, power(80, external: false, charging: false))

        #expect(try publications(plugin, power(80, external: true, charging: false)).first?.notice?.delivery == .show)
    }

    @Test
    func aPreviewShowsASampleWithoutMovingTheBaseline() throws {
        let plugin  = ChargingPlugin()
        let preview = try PluginActionEvent(feature: ChargingPlugin.feature, action: ChargingPlugin.preview, value: .bool(true))

        let shown = try #require(try publications(plugin, .action(preview)).first?.notice)

        #expect(shown.border == .chargingLowPower)
        #expect(try publications(plugin, power(19, external: true, charging: true)).isEmpty)
    }

    @Test
    func aRefreshOrAWakeShowsNothing() throws {
        let plugin = ChargingPlugin()

        #expect(try publications(plugin, .refresh).isEmpty)
        #expect(try publications(plugin, .wake).isEmpty)
    }

    @Test
    func theManifestDeclaresWhatTheNoticeUses() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == ChargingPlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "ChargingPlugin")
        #expect(feature.id == ChargingPlugin.feature)
        #expect(feature.surfaces.declares(.notice))
        #expect(feature.sources == [PluginPowerState.source])
        #expect(feature.components == [try PluginComponentReference(id: "power.battery", version: 1)])
        #expect(feature.actions == [ChargingPlugin.preview])
    }
}
