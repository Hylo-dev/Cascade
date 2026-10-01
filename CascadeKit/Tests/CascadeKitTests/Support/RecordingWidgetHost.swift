//
//  RecordingWidgetHost.swift
//  CascadeKit
//

@testable import CascadeKit

/// RecordingWidgetHost keeps the widgets the plugin surface router placed and removed.
@MainActor
final class RecordingWidgetHost: PluginWidgetHosting {

    private(set) var widgets: [WidgetIdentifier: NotchWidget] = [:]
    private(set) var registrations = 0

    func register(_ widget: NotchWidget) {
        registrations += 1
        widgets[widget.id] = widget
    }

    func unregisterWidget(id: WidgetIdentifier) {
        widgets[id] = nil
    }
}
