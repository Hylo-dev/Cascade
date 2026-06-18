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

    /// The notch's current discrete state.
    public private(set) var state: NotchState

    private let requestContent: () -> Void

    init(
        state         : NotchState,
        requestContent: @escaping () -> Void
    ) {
        self.state          = state
        self.requestContent = requestContent
    }

    /// Ask the host to rebuild this widget's content. Call this only when a
    /// declared input actually changed — never on a timer or per frame.
    public func setNeedsContent() {
        requestContent()
    }

    /// Keep the context's state in sync as the notch transitions. Internal: the
    /// host calls it, widgets only ever read `state`.
    func update(state: NotchState) {
        self.state = state
    }
}
