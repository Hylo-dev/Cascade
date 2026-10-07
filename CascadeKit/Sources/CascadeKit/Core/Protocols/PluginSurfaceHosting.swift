//
//  PluginSurfaceHosting.swift
//  CascadeKit
//

import Foundation

/// PluginSurfaceHosting is the part of the notch plugin surfaces need: placing a widget on the
/// grid and taking it off, showing a notice, enriching it and dismissing it, presenting a live
/// activity and ending it, and opening a widget's options page over the grid. The notch engine provides it; tests record it.
@MainActor
public protocol PluginSurfaceHosting: AnyObject {

    func register(_ widget: NotchWidget)

    func unregisterWidget(id: WidgetIdentifier)

    func showNotice(_ notice: any NotchTransientNotice)

    func updateNotice(_ notice: any NotchTransientNotice)

    func dismissActivity(id: String)

    func present(_ activity: any NotchLiveActivity)

    func endActivity(id: String)

    /// captureOptionsOrigin records a click on a visible widget's options opener, bound to the
    /// display and page it happened on. A hidden widget, or one that offers no options, gets nil.
    func captureOptionsOrigin(
        widgetID        : WidgetIdentifier,
        observedRevision: UInt64
    ) -> PluginOptionsOrigin?

    /// presentOptions shows the page for a still-valid origin and reports whether it did.
    func presentOptions(
        page     : any NotchContextualPage,
        leaseID  : UUID,
        origin   : PluginOptionsOrigin,
        onDismiss: @escaping @MainActor () -> Void
    ) -> Bool

    func dismissOptions(leaseID: UUID)
}

/// The defaults leave a host without an options page: nothing can be captured or presented.
public extension PluginSurfaceHosting {

    func captureOptionsOrigin(
        widgetID        : WidgetIdentifier,
        observedRevision: UInt64
    ) -> PluginOptionsOrigin? {
        nil
    }

    func presentOptions(
        page     : any NotchContextualPage,
        leaseID  : UUID,
        origin   : PluginOptionsOrigin,
        onDismiss: @escaping @MainActor () -> Void
    ) -> Bool {
        false
    }

    func dismissOptions(leaseID: UUID) {}
}
