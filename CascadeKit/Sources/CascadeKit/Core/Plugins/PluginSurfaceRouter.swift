//
//  PluginSurfaceRouter.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginEngine

/// PluginSurfaceRouter puts plugin publications where they belong on the notch, as the spec's
/// publication sink does: one store per publication, and for a widget one `PluginWidget` on the
/// grid, registered with its first content and removed with its withdrawal. Later publications
/// only update the store. A notice gets one store and one `PluginNotice`, shown again for every
/// publication and dismissed with its withdrawal. Activities are routed by the Music
/// sub-project; until then their publications are not shown.
@MainActor
public final class PluginSurfaceRouter {

    private let host      : any PluginSurfaceHosting
    private let sizes     : [PluginPublicationKey: GridSpan]
    private let submit    : (PluginActionRequest) -> Void
    private let visibility: (Bool, PluginPublicationKey) -> Void
    private var stores    : [PluginPublicationKey: PluginNodeStore] = [:]
    private var notices   : [PluginPublicationKey: PluginNotice] = [:]

    public init(
        host      : any PluginSurfaceHosting,
        manifests : [PluginManifest],
        submit    : @escaping (PluginActionRequest) -> Void,
        visibility: @escaping (Bool, PluginPublicationKey) -> Void
    ) {
        self.host       = host
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
        for change in changes {
            switch change.key.surface {
                case .widget  : route(widget: change)
                case .notice  : route(notice: change)
                case .activity: break
            }
        }

        for request in rejected {
            stores[request.key]?.reject(request)
        }
    }

    /// route places a widget with its first content, updates it after, and removes it with its
    /// withdrawal.
    private func route(widget change: PluginPublicationChange) {
        if change.content == nil {
            if stores.removeValue(forKey: change.key) != nil {
                host.unregisterWidget(id: Self.identifier(of: change.key))
            }
        } else if let store = stores[change.key] {
            store.apply(change)
        } else {
            place(change)
        }
    }

    /// route shows a notice for every publication and dismisses it with its withdrawal.
    private func route(notice change: PluginPublicationChange) {
        let key = change.key
        guard let content = change.content else {
            stores[key] = nil
            if notices.removeValue(forKey: key) != nil {
                host.dismissActivity(id: Self.identifier(of: key).rawValue)
            }
            return
        }
        guard let attributes = content.notice else { return }

        let store = stores[key] ?? PluginNodeStore(key: key, submit: submit)
        stores[key] = store
        store.apply(change)

        let notice = notices[key] ?? PluginNotice(
            id        : Self.identifier(of: key).rawValue,
            sourceID  : key.plugin.rawValue,
            store     : store,
            attributes: attributes,
            visibility: { [visibility] isVisible in visibility(isVisible, key) }
        )
        notices[key] = notice
        notice.update(attributes)
        host.showNotice(notice)
    }

    /// place makes the store for a widget's first content, fills it, then registers the widget,
    /// so the grid never shows an empty tile.
    private func place(_ change: PluginPublicationChange) {
        let key   = change.key
        let store = PluginNodeStore(key: key, submit: submit)
        store.apply(change)
        stores[key] = store

        host.register(
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
