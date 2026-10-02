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
/// publication, or only enriched in place when the publication asks to update, and dismissed with
/// its withdrawal. Activities keep their finite lifetime across revisions and end with withdrawal.
@MainActor
public final class PluginSurfaceRouter {

    /// components lists the tier-2 components these surfaces draw, for the engine's capabilities.
    public static let components: Set<String> = PluginComponentView.identifiers

    private let host      : any PluginSurfaceHosting
    private let sizes     : [PluginPublicationKey: [GridSpan]]
    private let submit    : (PluginActionRequest) -> Void
    private let visibility: (Bool, PluginPublicationKey) -> Void
    private var stores    : [PluginPublicationKey: PluginNodeStore] = [:]
    private var notices   : [PluginPublicationKey: PluginNotice] = [:]
    private var activities: [PluginPublicationKey: PluginActivity] = [:]

    public init(
        host      : any PluginSurfaceHosting,
        manifests : [PluginManifest],
        submit    : @escaping (PluginActionRequest) -> Void,
        visibility: @escaping (Bool, PluginPublicationKey) -> Void
    ) {
        self.host       = host
        self.submit     = submit
        self.visibility = visibility

        var sizes: [PluginPublicationKey: [GridSpan]] = [:]
        for manifest in manifests {
            for feature in manifest.features {
                if let declared = feature.surfaces.widget?.sizes {
                    sizes[PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget)] = declared.map(GridSpan.init)
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
                case .activity: route(activity: change)
            }
        }

        for request in rejected {
            stores[request.key]?.reject(request)
        }
    }

    /// route keeps one activity and its node store for the whole publication lifetime.
    /// Updating its revision does not extend its deadline or replace its visible controls.
    private func route(activity change: PluginPublicationChange) {
        let key = change.key
        guard change.content != nil else {
            stores[key] = nil
            if activities.removeValue(forKey: key) != nil {
                host.dismissActivity(id: Self.identifier(of: key).rawValue)
            }
            return
        }

        let store = stores[key] ?? PluginNodeStore(key: key, submit: submit)
        stores[key] = store
        store.apply(change)

        let activity = activities[key] ?? PluginActivity(
            id        : Self.identifier(of: key).rawValue,
            sourceID  : key.plugin.rawValue,
            store     : store,
            visibility: { [visibility] isVisible in visibility(isVisible, key) }
        )
        activities[key] = activity
        host.present(activity)
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
        switch attributes.delivery {
            case .show  : host.showNotice(notice)
            case .update: host.updateNotice(notice)
        }
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
                sizes     : sizes[key] ?? [],
                store     : store,
                visibility: { [visibility] isVisible in visibility(isVisible, key) }
            )
        )
    }

    private static func identifier(of key: PluginPublicationKey) -> WidgetIdentifier {
        let identifier = "plugin:" + key.plugin.rawValue + "/" + key.feature
        // Widget identities already live in saved arrangements. Only the new activity surface
        // needs a suffix to avoid colliding with its feature's notices in the live host.
        return WidgetIdentifier(key.surface == .activity ? identifier + "/activity" : identifier)
    }
}
