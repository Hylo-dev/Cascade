//
//  PluginSystemTests.swift
//  CascadeTests
//

import CascadeContracts
import CascadeKit
import CascadePlugins
import Foundation
import Testing
@testable import Cascade

extension PluginHostTests {

    /// PluginSystemTests run Cascade's plugin composition against the PluginHost bundled in the
    /// test host, with a recording grid in place of the notch.
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
            let plugins = PluginSystem(host: grid)
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
            let plugins = PluginSystem(host: grid)
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
            let plugins = PluginSystem(host: grid)
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
            let plugins = PluginSystem(host: grid, sources: [PluginVolumeState.source: VolumePluginSource(monitor: FakeVolumeMonitor())])
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
    }
}
