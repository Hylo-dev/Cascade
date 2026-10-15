//
//  RecordingSurfaceHost.swift
//  CascadeKit
//

import CoreGraphics
@testable import CascadeKit

/// RecordingSurfaceHost keeps what the plugin surface router placed, showed and removed.
@MainActor
final class RecordingSurfaceHost: PluginSurfaceHosting {

    private(set) var widgets      : [WidgetIdentifier: NotchWidget] = [:]
    private(set) var registrations = 0
    private(set) var shown        : [(notice: any NotchTransientNotice, revision: UInt64)] = []
    private(set) var dismissed    : [String] = []
    private(set) var updated      : [UInt64] = []

    private(set) var shownDetails: [(
        page       : any NotchContextualPage,
        displayID  : CGDirectDisplayID?,
        onDismiss  : @MainActor () -> Void,
        onPresented: @MainActor (Bool) -> Void
    )] = []
    private(set) var dismissedDetailIDs: [String] = []

    /// refusesDetails makes `showDetail` behave as a host whose display is not expanded does.
    var refusesDetails = false

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

    func updateNotice(_ notice: any NotchTransientNotice) {
        updated.append(notice.contentRevision)
    }

    func dismissActivity(id: String) {
        dismissed.append(id)
    }

    func showDetail(
        _ page      : any NotchContextualPage,
        on displayID: CGDirectDisplayID?,
        onDismiss   : @escaping @MainActor () -> Void,
        onPresented : @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        guard !refusesDetails else { return false }

        shownDetails.append((page, displayID, onDismiss, onPresented))
        return true
    }

    func dismissDetail(id: String) {
        dismissedDetailIDs.append(id)
    }
}
