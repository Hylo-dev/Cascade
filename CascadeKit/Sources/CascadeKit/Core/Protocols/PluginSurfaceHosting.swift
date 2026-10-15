//
//  PluginSurfaceHosting.swift
//  CascadeKit
//

import CoreGraphics

/// PluginSurfaceHosting is the part of the notch plugin surfaces need: placing a widget on the
/// grid and taking it off, showing a notice, enriching it and dismissing it, and opening one detail
/// page over the expanded surface. The notch engine provides it; tests record it.
@MainActor
public protocol PluginSurfaceHosting: AnyObject {

    func register(_ widget: NotchWidget)

    func unregisterWidget(id: WidgetIdentifier)

    func showNotice(_ notice: any NotchTransientNotice)

    func updateNotice(_ notice: any NotchTransientNotice)

    func dismissActivity(id: String)

    /// showDetail opens `page` over the expanded surface of `displayID`, or of the expanded display
    /// when nil, and returns true. It shows nothing, never calls `onDismiss` and returns false when
    /// that display is not expanded, so a caller that tracks the detail as visible can tell. Showing
    /// another detail ends this one first; `onDismiss` runs exactly once for every detail that was
    /// shown, however it ends.
    ///
    /// Closing the notch does not end the detail: it is kept and shown again by the next opening.
    /// `onPresented` reports it leaving the screen as the notch closes (false) and coming back as
    /// it reopens (true); the first showing is the `true` this function returns, and the end is
    /// `onDismiss`.
    @discardableResult
    func showDetail(
        _ page      : any NotchContextualPage,
        on displayID: CGDirectDisplayID?,
        onDismiss   : @escaping @MainActor () -> Void,
        onPresented : @escaping @MainActor (Bool) -> Void
    ) -> Bool

    /// dismissDetail closes the shown detail whose page has this id; any other id is ignored.
    func dismissDetail(id: String)
}
