//
//  RecordingSurfaceHost.swift
//  CascadeKit
//

@testable import CascadeKit

/// RecordingSurfaceHost keeps what the plugin surface router placed, showed and removed.
@MainActor
final class RecordingSurfaceHost: PluginSurfaceHosting {

    private(set) var widgets      : [WidgetIdentifier: NotchWidget] = [:]
    private(set) var registrations = 0
    private(set) var shown        : [(notice: any NotchTransientNotice, revision: UInt64)] = []
    private(set) var dismissed    : [String] = []

    func register(_ widget: NotchWidget) {
        registrations += 1
        widgets[widget.id] = widget
    }

    func unregisterWidget(id: WidgetIdentifier) {
        widgets[id] = nil
    }

    func showNotice(_ notice: any NotchTransientNotice) {
        shown.append((notice, notice.contentRevision))
    }

    func dismissActivity(id: String) {
        dismissed.append(id)
    }
}
