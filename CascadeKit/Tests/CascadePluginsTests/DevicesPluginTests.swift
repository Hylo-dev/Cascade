//
//  DevicesPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct DevicesPluginTests {

    private let context = PluginContext(plugin: DevicesPlugin.id)

    private static let airPods  = PluginBluetoothDevice(name: "AirPods Pro", symbolName: "airpodspro", batteryLevel: 68)
    private static let mouse    = PluginBluetoothDevice(name: "Magic Mouse", symbolName: "magicmouse.fill", batteryLevel: 40)
    private static let keyboard = PluginBluetoothDevice(name: "Magic Keyboard", symbolName: "keyboard.fill", batteryLevel: nil)
    private static let speaker  = PluginBluetoothDevice(name: "HomePod mini", symbolName: "homepodmini.fill", batteryLevel: 100)

    /// bluetooth is a state of the source that lists `devices`, as the event `eventID` of a
    /// connection, so two states can list the same devices and still be different events.
    private func bluetooth(
        _ devices  : [PluginBluetoothDevice],
        isAvailable: Bool = true,
        eventID    : UInt64 = 0
    ) throws -> PluginEvent {
        let state = PluginBluetoothState(
            deviceID        : eventID == 0 ? "" : "device-\(eventID)",
            name            : eventID == 0 ? "" : "Device \(eventID)",
            symbolName      : "",
            isConnected     : eventID != 0,
            battery         : nil,
            model           : .generic,
            productID       : nil,
            colorID         : nil,
            eventID         : eventID,
            revision        : 0,
            kind            : .connection,
            isAvailable     : isAvailable,
            connectedDevices: devices
        )

        return .source(try state.event())
    }

    private func root(of output: PluginOutput) throws -> PluginNode {
        let publication = try #require(output.publications.first)

        #expect(output.publications.count == 1)
        #expect(output.wake == nil)
        #expect(publication.feature == DevicesPlugin.feature)
        #expect(publication.surface == .widget)

        return try #require(publication.document).root
    }

    private func components(in node: PluginNode) -> [[String: PluginValue]] {
        PluginNodeSearch.kinds(in: node).compactMap { kind in
            if case .component("bluetooth.battery", 1, let parameters) = kind { return parameters }

            return nil
        }
    }

    // MARK: - The plugin

    @Test
    func noDeviceSaysSo() throws {
        let root = try root(of: DevicesPlugin().handle(try bluetooth([]), context: context))

        #expect(root.children.allSatisfy { PluginNodeSearch.texts(in: $0) == ["No devices"] })
        #expect(components(in: root).isEmpty)
    }

    @Test
    func aMacWhoseBluetoothDoesNotWorkSaysItIsOff() throws {
        let root = try root(of: DevicesPlugin().handle(try bluetooth([], isAvailable: false), context: context))

        #expect(root.children.allSatisfy { PluginNodeSearch.texts(in: $0) == ["Bluetooth is off"] })
        #expect(try ItalianStrings.value(of: "Bluetooth is off") == "Bluetooth spento")
        #expect(try ItalianStrings.value(of: "No devices") == "Nessun dispositivo")
    }

    /// The tall face lists up to four devices and the short one the first two, in the order they
    /// connected.
    @Test
    func threeDevicesTakeThreeRowsOnTheTallFaceAndTwoOnTheShortOne() throws {
        let root  = try root(of: DevicesPlugin().handle(try bluetooth([Self.airPods, Self.mouse, Self.keyboard]), context: context))
        let large = try #require(root.children.first)
        let short = try #require(root.children.last)

        #expect(root.kind == .viewThatFits(axes: .vertical))
        #expect(root.children.count == 2)
        #expect(large.children.count == 3)
        #expect(short.children.count == 2)
        #expect(PluginNodeSearch.texts(in: large) == ["AirPods Pro", "68%", "Magic Mouse", "40%", "Magic Keyboard"])
        #expect(PluginNodeSearch.texts(in: short) == ["AirPods Pro", "68%", "Magic Mouse", "40%"])
    }

    @Test
    func fourDevicesFillTheTallFace() throws {
        let root  = try root(of: DevicesPlugin().handle(try bluetooth([Self.airPods, Self.mouse, Self.keyboard, Self.speaker]), context: context))
        let large = try #require(root.children.first)

        #expect(large.children.count == 4)
        #expect(PluginNodeSearch.kinds(in: large).contains(.symbol(name: "homepodmini.fill")))
    }

    /// Each row is the device's symbol and name, and, when its charge is known, the charge and the
    /// kernel's ring; a device that reports no charge has neither.
    @Test
    func aDeviceWithoutABatteryHasNoBatteryComponent() throws {
        let root  = try root(of: DevicesPlugin().handle(try bluetooth([Self.airPods, Self.keyboard]), context: context))
        let large = try #require(root.children.first)
        let rows  = large.children

        #expect(rows.count == 2)
        #expect(PluginNodeSearch.kinds(in: rows[0]).contains(.symbol(name: "airpodspro")))
        #expect(components(in: rows[0]) == [["isConnected": .bool(true), "level": .number(68)]])
        #expect(PluginNodeSearch.kinds(in: rows[1]).contains(.symbol(name: "keyboard.fill")))
        #expect(components(in: rows[1]).isEmpty)
        #expect(PluginNodeSearch.texts(in: rows[1]) == ["Magic Keyboard"])
    }

    /// VoiceOver cannot read the ring, so the face says every device and every known charge.
    @Test
    func voiceOverReadsEveryDeviceAndItsCharge() throws {
        let root = try root(of: DevicesPlugin().handle(try bluetooth([Self.airPods, Self.keyboard]), context: context))

        #expect(PluginNodeSearch.accessibilityLabel(of: root) == "AirPods Pro, battery 68 percent, Magic Keyboard")
        #expect(try ItalianStrings.value(of: "%@, battery %lld percent") == "%1$@, batteria al %2$lld percento")
    }

    /// A Bluetooth state also says which device the latest event was about; the widget shows only
    /// the list, so a new event that leaves the list as it was publishes nothing.
    @Test
    func theSameListTwicePublishesOnce() throws {
        let plugin = DevicesPlugin()

        let first   = try plugin.handle(try bluetooth([Self.airPods], eventID: 1), context: context)
        let again   = try plugin.handle(try bluetooth([Self.airPods], eventID: 2), context: context)
        let charged = try plugin.handle(try bluetooth([PluginBluetoothDevice(name: "AirPods Pro", symbolName: "airpodspro", batteryLevel: 67)], eventID: 2), context: context)

        #expect(first.publications.count == 1)
        #expect(again.publications.isEmpty)
        #expect(charged.publications.count == 1)
    }

    @Test
    func aRefreshRepublishesTheLastListAndNothingBeforeOne() throws {
        let plugin = DevicesPlugin()

        let early   = try plugin.handle(.refresh, context: context)
        let first   = try plugin.handle(try bluetooth([Self.mouse]), context: context)
        let refresh = try plugin.handle(.refresh, context: context)

        #expect(early.publications.isEmpty)
        #expect(refresh.publications == first.publications)
    }

    @Test
    func anotherSourcesEventChangesNothing() throws {
        let plugin = DevicesPlugin()
        let power  = PluginEvent.source(try PluginPowerState(percentage: 50, isExternalPower: false, isCharging: false, isLowPowerMode: false).event())

        #expect(try plugin.handle(power, context: context).publications.isEmpty)
        #expect(try plugin.handle(.wake, context: context).publications.isEmpty)
    }

    // MARK: - The faces and the manifest

    /// ViewThatFits measures a face with the tile's width already given, so the tall face has a
    /// fixed height that a short tile cannot hold.
    @Test
    func theTallFaceIsChosenByItsFixedHeight() throws {
        let root  = try #require(try DevicesFace.publication(for: .baseline(isAvailable: true)).document).root
        let large = try #require(root.children.first)

        #expect(large.modifiers.contains { modifier in
            if case .frame(_, DevicesFace.largeHeight?, _, _, _) = modifier { return true }

            return false
        })
    }

    @Test
    func theManifestDeclaresBothTilesTheSourceAndOnlyTheRing() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == DevicesPlugin.id })
        let feature  = try #require(manifest.features.first)
        let document = try #require(try DevicesFace.publication(for: .baseline(isAvailable: true, connectedDevices: [Self.airPods])).document)

        #expect(manifest.execution.entryPoint == "DevicesPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == DevicesPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == [try PluginWidgetSize(columns: 2, rows: 1), try PluginWidgetSize(columns: 2, rows: 2)])
        #expect(feature.sources == [PluginBluetoothState.source])
        #expect(feature.components == [try PluginComponentReference(id: "bluetooth.battery", version: 1)])
        #expect(document.componentReferences == Set(feature.components))
        #expect(!FirstPartyPlugins.placedByDefault.contains(DevicesPlugin.id))
        #expect(FirstPartyPlugins.name(of: DevicesPlugin.id) == "Devices")
        #expect(try ItalianStrings.value(of: "Devices") == "Dispositivi")
    }
}
