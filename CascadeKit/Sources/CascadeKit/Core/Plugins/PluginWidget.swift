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

    /// openDetail opens the detail page of this widget's feature, and is nil when the feature
    /// declares none.
    let openDetail: (@MainActor () -> Void)?

    var size: GridSpan { sizes[0] }

    private let services  : PluginComponentServices?
    private let visibility: (Bool) -> Void

    /// init(id:sizes:store:services:openDetail:visibility:) takes the sizes the manifest declares,
    /// in its order; an empty list, which a valid manifest cannot produce, falls back to the
    /// clock's 4×1. The services and `openDetail` reach the components through the environment.
    init(
        id        : WidgetIdentifier,
        sizes     : [GridSpan],
        store     : PluginNodeStore,
        services  : PluginComponentServices? = nil,
        openDetail: (@MainActor () -> Void)? = nil,
        visibility: @escaping (Bool) -> Void
    ) {
        self.id         = id
        self.sizes      = sizes.isEmpty ? [GridSpan(columns: 4, rows: 1)] : sizes
        self.store      = store
        self.services   = services
        self.openDetail = openDetail
        self.visibility = visibility
    }

    func makeContentView() -> AnyView {
        AnyView(
            PluginDocumentView(store: store)
                .environment(\.pluginComponentServices, services)
                .environment(\.pluginOpenDetail, openDetail)
        )
    }

    func activate(in context: WidgetContext) {
        visibility(true)
    }

    func suspend() {
        visibility(false)
    }
}
