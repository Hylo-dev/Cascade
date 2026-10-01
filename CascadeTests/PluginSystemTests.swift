//
//  PluginSystemTests.swift
//  CascadeTests
//

import CascadeKit
import Foundation
import Testing
@testable import Cascade

/// PluginSystemTests run Cascade's plugin composition against the PluginHost bundled in the
/// test host, with a recording grid in place of the notch.
@MainActor
struct PluginSystemTests {

    @MainActor
    final class Grid: PluginWidgetHosting {

        var widgets: [WidgetIdentifier: NotchWidget] = [:]

        func register(_ widget: NotchWidget) {
            widgets[widget.id] = widget
        }

        func unregisterWidget(id: WidgetIdentifier) {
            widgets[id] = nil
        }
    }

    @Test
    func theBundledClockReachesTheNotchThroughPluginHost() async throws {
        let grid    = Grid()
        let plugins = PluginSystem(widgets: grid)
        plugins.start()

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while grid.widgets.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let widget = try #require(grid.widgets[WidgetIdentifier("plugin:com.cascade.clock/time")])
        #expect(widget.size == GridSpan(columns: 4, rows: 1))
    }
}
