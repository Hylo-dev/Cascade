//
//  PluginWidget.swift
//  CascadeKit
//

import SwiftUI

/// PluginWidget puts one plugin's widget publication on the notch grid. Its view observes the
/// publication's store, so a new publication redraws only the nodes it changed without the host
/// rebuilding anything, and activation and suspension tell the engine whether the widget is on
/// screen. The host's contract still takes an `AnyView` at this boundary; inside it, the
/// publication is drawn by nominal views.
@MainActor
final class PluginWidget: NotchWidget {

    static let kind = WidgetKind("com.cascade.plugin")

    let id   : WidgetIdentifier
    let sizes: [GridSpan]
    let store: PluginNodeStore

    var size: GridSpan { sizes[0] }

    private let visibility: (Bool) -> Void

    /// init(id:sizes:store:visibility:) takes the sizes the manifest declares, in its order;
    /// an empty list, which a valid manifest cannot produce, falls back to the clock's 4×1.
    init(
        id        : WidgetIdentifier,
        sizes     : [GridSpan],
        store     : PluginNodeStore,
        visibility: @escaping (Bool) -> Void
    ) {
        self.id         = id
        self.sizes      = sizes.isEmpty ? [GridSpan(columns: 4, rows: 1)] : sizes
        self.store      = store
        self.visibility = visibility
    }

    func makeContentView() -> AnyView {
        AnyView(PluginDocumentView(store: store))
    }

    func activate(in context: WidgetContext) {
        visibility(true)
    }

    func suspend() {
        visibility(false)
    }
}
