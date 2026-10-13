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
/// its withdrawal. A detail publication gets one store and one `PluginDetail`, kept but not shown:
/// the widget of the same feature opens it, and its withdrawal closes it. Activities are routed
/// by the Music sub-project; until then their publications are not shown.
@MainActor
public final class PluginSurfaceRouter {

    /// components lists the tier-2 components these surfaces draw, for the engine's capabilities.
    public static let components: Set<String> = PluginComponentView.identifiers

    private let host       : any PluginSurfaceHosting
    private let sizes      : [PluginPublicationKey: [GridSpan]]
    private let services   : PluginComponentServices
    private let hasDetail  : Set<PluginPublicationKey>
    private let submit     : (PluginActionRequest) -> Void
    private let visibility : (Bool, PluginPublicationKey) -> Void
    private var stores     : [PluginPublicationKey: PluginNodeStore] = [:]
    private var notices    : [PluginPublicationKey: PluginNotice] = [:]
    private var details    : [PluginPublicationKey: PluginDetail] = [:]
    private var openDetails: Set<PluginPublicationKey> = []

    public init(
        host      : any PluginSurfaceHosting,
        manifests : [PluginManifest],
        services  : PluginComponentServices? = nil,
        submit    : @escaping (PluginActionRequest) -> Void,
        visibility: @escaping (Bool, PluginPublicationKey) -> Void
    ) {
        self.host       = host
        self.services   = services ?? PluginComponentServices()
        self.submit     = submit
        self.visibility = visibility

        var sizes    : [PluginPublicationKey: [GridSpan]] = [:]
        var hasDetail: Set<PluginPublicationKey> = []
        for manifest in manifests {
            for feature in manifest.features {
                if feature.surfaces.detail != nil {
                    hasDetail.insert(PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .detail))
                }
                if let declared = feature.surfaces.widget?.sizes {
                    sizes[PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget)] = declared.map(GridSpan.init)
                }
            }
        }
        self.sizes     = sizes
        self.hasDetail = hasDetail
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
                case .detail  : route(detail: change)
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

    /// route keeps a detail's store and page from its first content, updates them after, and
    /// closes the page with the withdrawal. Nothing is shown until the widget asks.
    private func route(detail change: PluginPublicationChange) {
        let key = change.key
        guard change.content != nil else {
            stores[key]  = nil
            details[key] = nil
            if openDetails.remove(key) != nil {
                host.dismissDetail(id: PluginDetail.identifier(of: key))
            }
            return
        }

        if let store = stores[key] {
            store.apply(change)
            return
        }

        let store = PluginNodeStore(key: key, submit: submit)
        store.apply(change)
        stores[key]  = store
        details[key] = PluginDetail(
            key     : key,
            store   : store,
            services: services,
            dismiss : { [host] in host.dismissDetail(id: PluginDetail.identifier(of: key)) }
        )
    }

    /// open shows a feature's detail on the expanded display, where the click that asks for it
    /// happened, and reports it visible once the host has ended any detail it replaces; the host
    /// reports it hidden through `onDismiss`, exactly once, however it ends. A host that refuses
    /// the show never calls `onDismiss`, so nothing is tracked or reported then. Without a detail
    /// publication yet there is nothing to open.
    private func open(detail key: PluginPublicationKey) {
        guard let detail = details[key] else { return }

        let isShown = host.showDetail(
            detail,
            on       : nil,
            onDismiss: { [weak self, visibility] in
                self?.openDetails.remove(key)
                visibility(false, key)
            }
        )
        guard isShown else { return }

        openDetails.insert(key)
        visibility(true, key)
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

        let detailKey = PluginPublicationKey(plugin: key.plugin, feature: key.feature, surface: .detail)
        var openDetail: (@MainActor () -> Void)?
        if hasDetail.contains(detailKey) {
            openDetail = { [weak self] in self?.open(detail: detailKey) }
        }

        host.register(
            PluginWidget(
                id        : Self.identifier(of: key),
                sizes     : sizes[key] ?? [],
                store     : store,
                services  : services,
                openDetail: openDetail,
                visibility: { [visibility] isVisible in visibility(isVisible, key) }
            )
        )
    }

    private static func identifier(of key: PluginPublicationKey) -> WidgetIdentifier {
        WidgetIdentifier("plugin:" + key.plugin.rawValue + "/" + key.feature)
    }
}
