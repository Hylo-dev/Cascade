//
//  WidgetContext.swift
//  CascadeKit
//

import Foundation

/// WidgetContext is the typed seam a widget talks to the host through.
///
/// A widget never reaches into the engine: it is handed a context at activation
/// and uses it to read the current state and to ask for a content refresh when
/// one of its own inputs changed. Keeping this surface tiny is what enforces
/// the "widgets are decoupled and cheap" contract — there is simply no API here
/// to poll, block, or touch the panel.
@MainActor
public final class WidgetContext {

    /// state is the host's current NotchState. Widgets only read it; the host
    /// writes it through `update(state:)`, and a revoked context stops following
    /// transitions.
    public private(set) var state: NotchState

    private var requestContent: (() -> Void)?

    init(
        state         : NotchState,
        requestContent: @escaping () -> Void
    ) {
        self.state          = state
        self.requestContent = requestContent
    }

    /// setNeedsContent asks the host to rebuild this widget's content. Call this
    /// only when a declared input actually changed — never on a timer or per frame.
    public func setNeedsContent() {
        requestContent?()
    }

    /// update keeps the context's state in sync as the notch transitions.
    /// Internal: the host calls it, widgets only ever read `state`.
    func update(state: NotchState) {
        guard requestContent != nil else { return }
        self.state = state
    }

    /// revoke makes retained copies inert before the matching widget is suspended.
    func revoke() {
        requestContent = nil
    }
}
