//
//  PluginSystemTests.swift
//  CascadeTests
//

import CascadeContracts
import CascadeKit
import CascadePluginEngine
import CascadePlugins
import Foundation
import Synchronization
import Testing
@testable import Cascade

extension PluginHostTests {

    /// PluginSystemTests run Cascade's plugin composition against the PluginHost bundled in the
    /// test host, with a recording grid in place of the notch. Every system gets a fake Bluetooth
    /// source in place of PluginHost's, so no test asks macOS for Bluetooth access.
    @MainActor
    struct PluginSystemTests {

        @MainActor
        final class Grid: PluginSurfaceHosting {

            var widgets: [WidgetIdentifier: NotchWidget] = [:]
            var notices: [any NotchTransientNotice] = []

            func register(_ widget: NotchWidget) {
                widgets[widget.id] = widget
            }

            func unregisterWidget(id: WidgetIdentifier) {
                widgets[id] = nil
            }

            func showNotice(_ notice: any NotchTransientNotice) {
                notices.append(notice)
            }

            func updateNotice(_ notice: any NotchTransientNotice) {}

            func dismissActivity(id: String) {}
        }

        @Test
        func theBundledClockReachesTheNotchThroughPluginHost() async throws {
            let grid    = Grid()
            let plugins = PluginSystem(host: grid, sources: [PluginBluetoothState.source: FakeBluetoothSource()])
            plugins.start()

            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while grid.widgets.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            let widget = try #require(grid.widgets[WidgetIdentifier("plugin:com.cascade.clock/time")])
            #expect(widget.size == GridSpan(columns: 4, rows: 2))
        }

        @Test
        func aChargingPreviewReachesTheNoticeHostThroughPluginHost() async throws {
            let grid    = Grid()
            let plugins = PluginSystem(host: grid, sources: [PluginBluetoothState.source: FakeBluetoothSource()])
            plugins.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while grid.widgets.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            plugins.invoke(ChargingPlugin.preview, value: .bool(true), feature: ChargingPlugin.feature, of: ChargingPlugin.id)
            while grid.notices.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            let notice   = try #require(grid.notices.first)
            let strings  = try #require(Bundle.main.url(forResource: "CascadeKit_CascadePlugins", withExtension: "bundle").flatMap(Bundle.init(url:)))
            let charging = strings.localizedString(forKey: "Charging", value: nil, table: "ChargingNotice")
            #expect(notice.borderAppearance == .chargingLowPower)
            #expect(notice.compactPreferredSideWidth == 116)
            #expect(notice.accessibilityLabel.hasPrefix(charging), "PluginHost speaks the language Cascade speaks")
        }

        @Test
        func aSwitchedOffPluginIsNotInvoked() async throws {
            let grid    = Grid()
            let plugins = PluginSystem(host: grid, sources: [PluginBluetoothState.source: FakeBluetoothSource()])
            plugins.setEnabled(false, for: ChargingPlugin.id)
            plugins.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while grid.widgets.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            plugins.invoke(ChargingPlugin.preview, value: .bool(false), feature: ChargingPlugin.feature, of: ChargingPlugin.id)
            try await Task.sleep(for: .seconds(1))

            #expect(grid.notices.isEmpty)
        }

        @Test
        func aVolumePreviewReachesTheNoticeHostThroughPluginHost() async throws {
            let grid    = Grid()
            let plugins = PluginSystem(
                host   : grid,
                sources: [
                    PluginVolumeState.source   : VolumePluginSource(monitor: FakeVolumeMonitor()),
                    PluginBluetoothState.source: FakeBluetoothSource(),
                ]
            )
            plugins.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while grid.widgets.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            plugins.invoke(VolumePlugin.preview, feature: VolumePlugin.feature, of: VolumePlugin.id)
            while grid.notices.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            let notice = try #require(grid.notices.first)
            #expect(notice.displayDuration == 1.8)
            #expect(notice.borderAppearance == nil)
        }
        @Test
        func aBluetoothConnectionReachesTheNoticeHostAndItsObserverThroughPluginHost() async throws {
            let grid      = Grid()
            let bluetooth = FakeBluetoothSource()
            let observed  = ObservedStates()
            let plugins   = PluginSystem(host: grid, sources: [PluginBluetoothState.source: bluetooth])
            plugins.observe(PluginBluetoothState.source) { event in observed.record(event) }
            plugins.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while bluetooth.starts == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            // The plugin's first state is a silent baseline; should the connection reach its
            // mailbox before it handled the baseline, the two coalesce, so a second one follows.
            bluetooth.send(Self.airPods(eventID: 1))
            try await Task.sleep(for: .milliseconds(300))
            bluetooth.send(Self.airPods(eventID: 2))
            while grid.notices.count < 1 || observed.eventIDs.count < 3, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            let notice = try #require(grid.notices.last)
            #expect(notice.compactPreferredSideWidth == 40)
            #expect(notice.borderAppearance == .neutral)
            #expect(notice.displayDuration == 4)
            #expect(notice.accessibilityLabel.hasPrefix("AirPods Pro, "))
            #expect(observed.eventIDs == [0, 1, 2], "Cascade sees every state, before the engine coalesces them")
        }

        @Test
        func aBluetoothPreviewReachesTheNoticeHostThroughPluginHost() async throws {
            let grid    = Grid()
            let plugins = PluginSystem(host: grid, sources: [PluginBluetoothState.source: FakeBluetoothSource()])
            plugins.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while grid.widgets.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            plugins.invoke(BluetoothPlugin.preview, feature: BluetoothPlugin.feature, of: BluetoothPlugin.id)
            while grid.notices.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            let notice  = try #require(grid.notices.first)
            let strings = try #require(Bundle.main.url(forResource: "CascadeKit_CascadePlugins", withExtension: "bundle").flatMap(Bundle.init(url:)))
            let sample  = strings.localizedString(forKey: "AirPods · Preview", value: nil, table: "BluetoothNotice")
            #expect(notice.compactPreferredSideWidth == 40)
            #expect(notice.borderAppearance == .neutral)
            #expect(notice.accessibilityLabel.hasPrefix(sample + ", "))
        }

        @Test
        func aSwitchedOffBluetoothPluginNeverStartsItsSource() async throws {
            let grid      = Grid()
            let bluetooth = FakeBluetoothSource()
            let plugins   = PluginSystem(host: grid, sources: [PluginBluetoothState.source: bluetooth])
            plugins.setEnabled(false, for: BluetoothPlugin.id)
            plugins.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while grid.widgets.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(500))

            #expect(bluetooth.starts == 0)
        }

        @Test
        func theEngineStatusReachesTheApp() async throws {
            let grid     = Grid()
            let plugins  = PluginSystem(host: grid, sources: [PluginBluetoothState.source: FakeBluetoothSource()])
            var statuses = [PluginEngineStatus]()
            plugins.statusHandler = { statuses.append($0) }
            plugins.start()

            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while statuses.last?.host != .running || statuses.last?.plugins.isEmpty != false, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }

            let status = try #require(statuses.last)
            #expect(status.host == .running)
            #expect(Set(status.plugins.keys) == Set(FirstPartyPlugins.manifests().map(\.id)))
            #expect(status.plugins.values.allSatisfy { $0 == .active })
        }

        private static func airPods(eventID: UInt64) -> PluginBluetoothState {
            PluginBluetoothState(
                deviceID   : "AA-BB-CC-DD-EE-FF",
                name       : "AirPods Pro",
                symbolName : "airpodspro",
                isConnected: true,
                battery    : PluginBluetoothBattery(level: 68, left: 72, right: 68, caseLevel: 81),
                model      : .airPodsPro,
                productID  : 0x200E,
                colorID    : nil,
                eventID    : eventID,
                revision   : 0,
                kind       : .connection,
                isAvailable: true
            )
        }
    }
}

/// ObservedStates records the event numbers of the Bluetooth states an observer saw.
private nonisolated final class ObservedStates: Sendable {

    private let states = Mutex<[UInt64]>([])

    var eventIDs: [UInt64] {
        states.withLock { $0 }
    }

    func record(_ event: PluginSourceEvent) {
        guard let state = PluginBluetoothState(event) else { return }

        states.withLock { $0.append(state.eventID) }
    }
}
