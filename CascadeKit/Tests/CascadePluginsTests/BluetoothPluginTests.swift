//
//  BluetoothPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Testing

@testable import CascadePlugins

/// BluetoothPluginTests check that the plugin behaves as Cascade's Bluetooth notice did. The
/// package's command line does not compile string catalogs, so the sentences read in English.
@Suite
struct BluetoothPluginTests {

    private let context = PluginContext(plugin: BluetoothPlugin.id)

    private func bluetooth(
        _ eventID  : UInt64,
        revision   : UInt64 = 0,
        name       : String = "AirPods Pro",
        isConnected: Bool = true,
        battery    : PluginBluetoothBattery? = PluginBluetoothBattery(level: 68, left: 72, right: 68, caseLevel: 81),
        model      : PluginBluetoothDeviceModel = .airPodsPro,
        productID  : UInt16? = 0x200E,
        kind       : PluginBluetoothEventKind = .connection
    ) throws -> PluginEvent {
        let state = eventID == 0
            ? PluginBluetoothState.baseline(isAvailable: true)
            : PluginBluetoothState(
                deviceID   : "AA-BB-CC-DD-EE-FF",
                name       : name,
                symbolName : model == .generic ? "keyboard" : "airpodspro",
                isConnected: isConnected,
                battery    : battery,
                model      : model,
                productID  : productID,
                colorID    : nil,
                eventID    : eventID,
                revision   : revision,
                kind       : kind,
                isAvailable: true
            )

        return .source(try state.event())
    }

    private func publications(
        _ plugin: BluetoothPlugin,
        _ event : PluginEvent
    ) throws -> [PluginPublication] {
        try plugin.handle(event, context: context).publications
    }

    private func deliveries(
        _ plugin: BluetoothPlugin,
        _ events: [PluginEvent]
    ) throws -> [PluginNoticeDelivery?] {
        try events.map { try publications(plugin, $0).first?.notice?.delivery }
    }

    @Test
    func theFirstStateIsSilentEvenWhenItIsAConnection() throws {
        #expect(try deliveries(BluetoothPlugin(), [bluetooth(0), bluetooth(1)]) == [nil, .show])
        #expect(try deliveries(BluetoothPlugin(), [bluetooth(3), bluetooth(3, revision: 1), bluetooth(4)]) == [nil, nil, .show])
    }

    @Test
    func aNewConnectionShowsTheNoticeAsCascadeDrewIt() throws {
        let plugin = BluetoothPlugin()
        _ = try publications(plugin, bluetooth(0))

        let shown   = try #require(try publications(plugin, bluetooth(1)).first)
        let notice  = try #require(shown.notice)
        let regions = try #require(shown.document?.root.children)

        #expect(shown.surface == .notice)
        #expect(shown.feature == BluetoothPlugin.feature)
        #expect(notice.delivery == .show)
        #expect(notice.duration == 4)
        #expect(notice.border == .neutral)
        #expect(notice.compactWidth == 40)
        #expect(notice.accessibilityLabel == "AirPods Pro, Connected, Battery, 68 percent, Left, 72 percent, Right, 68 percent, Case, 81 percent")
        #expect(regions.count == 3)
        #expect(regions[0].kind == .component(id: "bluetooth.device", version: 1, parameters: ["model": .string("airPodsPro"), "productID": .number(0x200E), "fallbackSymbol": .string("airpodspro")]))
        #expect(regions[1].kind == .component(id: "bluetooth.battery", version: 1, parameters: ["level": .number(68), "isConnected": .bool(true)]))
        #expect(regions[2].kind == regions[1].kind)
        #expect(shown.document?.componentReferences == [try PluginComponentReference(id: "bluetooth.device", version: 1), try PluginComponentReference(id: "bluetooth.battery", version: 1)])
    }

    @Test
    func aDeviceTheSystemCannotIdentifyShowsItsSymbol() throws {
        let plugin = BluetoothPlugin()
        _ = try publications(plugin, bluetooth(0))

        let shown = try #require(try publications(plugin, bluetooth(1, name: "Keyboard", battery: nil, model: .generic, productID: nil)).first)

        #expect(shown.document?.root.children.first?.kind == .symbol(name: "keyboard"))
        #expect(shown.notice?.accessibilityLabel == "Keyboard, Connected, Battery unavailable")
    }

    @Test
    func enrichmentOnlyUpdatesTheNoticeOfItsOwnEvent() throws {
        let events = [
            try bluetooth(0),
            try bluetooth(1),
            try bluetooth(1, revision: 1),
            try bluetooth(1, revision: 1),
            try bluetooth(2),
            try bluetooth(1, revision: 2),
            try bluetooth(2, revision: 1),
        ]

        #expect(try deliveries(BluetoothPlugin(), events) == [nil, .show, .update, nil, .show, nil, .update])
    }

    @Test
    func aDisconnectionAndAudioComingBackAreNoticesToo() throws {
        let plugin = BluetoothPlugin()
        _ = try publications(plugin, bluetooth(0))

        let disconnected = try #require(try publications(plugin, bluetooth(1, isConnected: false)).first)
        let routed       = try #require(try publications(plugin, bluetooth(2, kind: .audioRoute)).first)

        #expect(disconnected.notice?.accessibilityLabel == "AirPods Pro, Disconnected, Battery unavailable")
        #expect(disconnected.document?.root.children[1].kind == .component(id: "bluetooth.battery", version: 1, parameters: ["level": .number(68), "isConnected": .bool(false)]))
        #expect(routed.notice?.accessibilityLabel.hasPrefix("AirPods Pro, Audio on Mac, ") == true)
    }

    @Test
    func aBaselineForgetsTheLastEventSilently() throws {
        #expect(try deliveries(BluetoothPlugin(), [bluetooth(0), bluetooth(5), bluetooth(0), bluetooth(1)]) == [nil, .show, nil, .show])
    }

    @Test
    func aPreviewShowsTheSampleAndALateReadingCannotOverwriteIt() throws {
        let plugin  = BluetoothPlugin()
        let preview = try PluginActionEvent(feature: BluetoothPlugin.feature, action: BluetoothPlugin.preview)
        _ = try publications(plugin, bluetooth(0))
        _ = try publications(plugin, bluetooth(1))

        let sample = try #require(try publications(plugin, .action(preview)).first)

        #expect(sample.notice?.delivery == .show)
        #expect(sample.notice?.accessibilityLabel == "AirPods · Preview, Connected, Battery, 68 percent, Left, 72 percent, Right, 68 percent, Case, 81 percent")
        #expect(sample.document?.root.children.first?.kind == .component(id: "bluetooth.device", version: 1, parameters: ["model": .string("airPodsPro"), "productID": .number(0x200E), "fallbackSymbol": .string("airpodspro")]))
        #expect(try deliveries(plugin, [bluetooth(1, revision: 1), bluetooth(2)]) == [nil, .show])
    }

    @Test
    func aRefreshOrAWakeShowsNothing() throws {
        let plugin = BluetoothPlugin()

        #expect(try publications(plugin, .refresh).isEmpty)
        #expect(try publications(plugin, .wake).isEmpty)
    }

    @Test
    func theManifestDeclaresWhatTheNoticeUses() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == BluetoothPlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "BluetoothPlugin")
        #expect(feature.id == BluetoothPlugin.feature)
        #expect(feature.surfaces.declares(.notice))
        #expect(feature.sources == [PluginBluetoothState.source])
        #expect(feature.components == [try PluginComponentReference(id: "bluetooth.device", version: 1), try PluginComponentReference(id: "bluetooth.battery", version: 1)])
        #expect(feature.actions == [BluetoothPlugin.preview])
    }
}
