//
//  PluginOptionsOrigin.swift
//  CascadeKit
//

/// PluginOptionsOrigin is the host's record of one click that may open a widget's options
/// page: the widget it came from and the publication revision the user saw. Only the notch
/// creates one, when a visible widget's opener is pressed, so a plugin cannot mint it. It is
/// revocable and never copied: the page's controls hold this exact instance, and revoking it
/// makes every one of them, and any acceptance still on its way, inert at once.
@MainActor
public final class PluginOptionsOrigin {

    let widgetID        : WidgetIdentifier
    let observedRevision: UInt64

    public private(set) var isValid = true

    init(
        widgetID        : WidgetIdentifier,
        observedRevision: UInt64
    ) {
        self.widgetID         = widgetID
        self.observedRevision = observedRevision
    }

    func revoke() {
        isValid = false
    }
}
