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

    let id                : WidgetIdentifier
    let sizes             : [GridSpan]
    let store             : PluginNodeStore
    let supportsFullscreen: Bool

    var size: GridSpan { sizes[0] }

    private let visibility: (Bool) -> Void

    /// init(id:sizes:store:visibility:supportsFullscreen:) takes the sizes the manifest declares, in its order;
    /// an empty list, which a valid manifest cannot produce, falls back to the clock's 4×1.
    init(
        id                : WidgetIdentifier,
        sizes             : [GridSpan],
        store             : PluginNodeStore,
        visibility        : @escaping (Bool) -> Void,
        supportsFullscreen: Bool = false
    ) {
        self.id                 = id
        self.sizes              = sizes.isEmpty ? [GridSpan(columns: 4, rows: 1)] : sizes
        self.store              = store
        self.visibility         = visibility
        self.supportsFullscreen = supportsFullscreen
    }

    func makeContentView() -> AnyView {
        let content = PluginDocumentView(store: store)
        guard supportsFullscreen else { return AnyView(content) }

        // The menu reaches the options from every size, including a face too small to show
        // the opener.
        return AnyView(content.contextMenu {
            if store.optionsButton != nil {
                Button(String(localized: "Options", bundle: .module), action: openOptions)
            }
        })
    }

    /// openOptions always reads the current opener, including at the icon-only size.
    func openOptions() {
        guard supportsFullscreen, let button = store.optionsButton else { return }
        store.press(button)
    }

    func activate(in context: WidgetContext) {
        visibility(true)
    }

    func suspend() {
        visibility(false)
    }
}
