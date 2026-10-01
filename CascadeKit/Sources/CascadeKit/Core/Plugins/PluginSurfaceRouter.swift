//
//  PluginSurfaceRouter.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginEngine

/// PluginSurfaceRouter puts plugin publications where they belong on the notch, as the spec's
/// publication sink does: one store per publication, and for a widget one `PluginWidget` on the
/// grid, registered with its first content and removed with its withdrawal. Later publications
/// only update the store. Activities and notices are routed by the plans that bring their
/// surfaces; until then their publications are not shown.
@MainActor
public final class PluginSurfaceRouter {

    private let widgets   : any PluginWidgetHosting
    private let sizes     : [PluginPublicationKey: GridSpan]
    private let submit    : (PluginActionRequest) -> Void
    private let visibility: (Bool, PluginPublicationKey) -> Void
    private var stores    : [PluginPublicationKey: PluginNodeStore] = [:]

    public init(
        widgets   : any PluginWidgetHosting,
        manifests : [PluginManifest],
        submit    : @escaping (PluginActionRequest) -> Void,
        visibility: @escaping (Bool, PluginPublicationKey) -> Void
    ) {
        self.widgets    = widgets
        self.submit     = submit
        self.visibility = visibility

        var sizes: [PluginPublicationKey: GridSpan] = [:]
        for manifest in manifests {
            for feature in manifest.features {
                if let size = feature.surfaces.widget?.sizes.first {
                    sizes[PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget)] = GridSpan(size)
                }
            }
        }
        self.sizes = sizes
    }

    /// makeSink returns the engine's sink for these surfaces: it carries every delivery to the
    /// main thread in one hop and applies it here.
    public func makeSink() -> any PluginPublicationSink {
        PluginSurfaceRelay { [weak self] changes, rejected in
            self?.apply(changes, rejected: rejected)
        }
    }

    func apply(
        _ changes: [PluginPublicationChange],
        rejected : [PluginActionRequest]
    ) {
        for change in changes where change.key.surface == .widget {
            if change.content == nil {
                if stores.removeValue(forKey: change.key) != nil {
                    widgets.unregisterWidget(id: Self.identifier(of: change.key))
                }
            } else if let store = stores[change.key] {
                store.apply(change)
            } else {
                place(change)
            }
        }

        for request in rejected {
            stores[request.key]?.reject(request)
        }
    }

    /// place makes the store for a widget's first content, fills it, then registers the widget,
    /// so the grid never shows an empty tile.
    private func place(_ change: PluginPublicationChange) {
        let key   = change.key
        let store = PluginNodeStore(key: key, submit: submit)
        store.apply(change)
        stores[key] = store

        widgets.register(
            PluginWidget(
                id        : Self.identifier(of: key),
                size      : sizes[key] ?? GridSpan(columns: 4, rows: 1),
                store     : store,
                visibility: { [visibility] isVisible in visibility(isVisible, key) }
            )
        )
    }

    private static func identifier(of key: PluginPublicationKey) -> WidgetIdentifier {
        WidgetIdentifier("plugin:" + key.plugin.rawValue + "/" + key.feature)
    }
}
