//
//  PluginSurfaceRouter.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginEngine
import Foundation

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

    private let host          : any PluginSurfaceHosting
    private let sizes         : [PluginPublicationKey: [GridSpan]]
    private let submit        : (PluginActionRequest) -> Void
    private let visibility    : (Bool, PluginPublicationKey) -> Void
    private let submitAccepted: ((PluginActionRequest, @escaping @MainActor @Sendable () -> Void) -> Void)?
    private let fullscreen    : Set<PluginPublicationKey>
    private var publicationIDs: [PluginPublicationKey: PublicationID] = [:]
    private var options: OptionsBinding?

    private struct OptionsBinding {

        let key    : PluginPublicationKey
        let origin : AddonOptionsOrigin
        let store  : PluginNodeStore
        let leaseID: UUID
        let page   : PluginOptionsPage
        var isPresented = false
    }

    private var stores    : [PluginPublicationKey: PluginNodeStore] = [:]
    private var notices   : [PluginPublicationKey: PluginNotice] = [:]
    private var activities: [PluginPublicationKey: PluginActivity] = [:]

    public init(
        host          : any PluginSurfaceHosting,
        manifests     : [PluginManifest],
        submit        : @escaping (PluginActionRequest) -> Void,
        visibility    : @escaping (Bool, PluginPublicationKey) -> Void,
        submitAccepted: ((PluginActionRequest, @escaping @MainActor @Sendable () -> Void) -> Void)? = nil
    ) {
        self.host           = host
        self.submit         = submit
        self.visibility     = visibility
        self.submitAccepted = submitAccepted

        var sizes: [PluginPublicationKey: [GridSpan]] = [:]
        var fullscreen = Set<PluginPublicationKey>()
        for manifest in manifests {
            for feature in manifest.features {
                if let declared = feature.surfaces.widget?.sizes {
                    sizes[PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget)] = declared.map(GridSpan.init)
                    if feature.supportsFullscreen {
                        fullscreen.insert(PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget))
                    }
                }
            }
        }
        self.sizes = sizes
        self.fullscreen = fullscreen
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
            if options?.key == change.key { clearOptions() }
            publicationIDs[change.key] = nil
            if stores.removeValue(forKey: change.key) != nil {
                host.unregisterWidget(id: Self.identifier(of: change.key))
            }
        } else if let store = stores[change.key] {
            store.apply(change)
            if let binding = options, binding.key == change.key {
                if !binding.isPresented || store.optionsRoot == nil || !binding.origin.isValid {
                    clearOptions()
                } else {
                    _ = host.presentOptions(page: binding.page, leaseID: binding.leaseID, origin: binding.origin, onDismiss: { [weak self, origin = binding.origin] in
                        self?.didDismiss(origin)
                    })
                }
            }
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
        let store = PluginNodeStore(key: key, submit: { [weak self] request in self?.submitWidget(request) })
        store.apply(change)
        stores[key] = store
        if let addonID = AddonID(rawValue: key.plugin.rawValue) {
            publicationIDs[key] = PublicationID(addonID: addonID, instanceID: UUID(), sessionID: UUID())
        }

        host.register(
            PluginWidget(
                id        : Self.identifier(of: key),
                sizes     : sizes[key] ?? [],
                store     : store,
                visibility: { [visibility] isVisible in visibility(isVisible, key) },
                supportsFullscreen: fullscreen.contains(key)
            )
        )
    }

    /// submitWidget captures the genuine mounted origin before the broker hop. Its
    /// acceptance closure holds that exact click, so equal late requests cannot win.
    private func submitWidget(_ request: PluginActionRequest) {
        guard let store = stores[request.key], store.revision == request.revision else { return }
        if store.isOptionsNode(request.node) {
            guard let binding = options, binding.key == request.key,
                  binding.isPresented, binding.origin.isValid, binding.store === store
            else { return }
            submit(request)
            return
        }
        guard store.optionsButton?.id == request.node else {
            submit(request)
            return
        }
        guard fullscreen.contains(request.key), let submitAccepted,
              let publicationID = publicationIDs[request.key],
              let origin = host.capturePluginOptionsOrigin(
                  widgetID        : Self.identifier(of: request.key),
                  publicationID   : publicationID,
                  observedRevision: request.revision
              )
        else { return }
        clearOptions()
        let binding = OptionsBinding(
            key    : request.key,
            origin : origin,
            store  : store,
            leaseID: UUID(),
            page   : PluginOptionsPage(id: Self.identifier(of: request.key).rawValue + "/options", store: store)
        )
        options = binding
        submitAccepted(request) { [weak self, origin] in self?.acceptOptions(origin) }
    }

    private func acceptOptions(_ origin: AddonOptionsOrigin) {
        guard var binding = options, binding.origin === origin, origin.isValid,
              stores[binding.key] === binding.store,
              binding.store.revision == origin.observedRevision,
              binding.store.optionsRoot != nil
        else { return }
        guard host.presentOptions(page: binding.page, leaseID: binding.leaseID, origin: origin, onDismiss: { [weak self, origin] in
            self?.didDismiss(origin)
        }) else { clearOptions(); return }
        binding.isPresented = true
        options = binding
    }

    private func didDismiss(_ origin: AddonOptionsOrigin) {
        guard options?.origin === origin else { return }
        origin.revoke()
        options = nil
    }

    private func clearOptions() {
        guard let binding = options else { return }
        options = nil
        binding.origin.revoke()
        if binding.isPresented { host.dismissOptions(leaseID: binding.leaseID) }
    }

    private static func identifier(of key: PluginPublicationKey) -> WidgetIdentifier {
        let identifier = "plugin:" + key.plugin.rawValue + "/" + key.feature
        // Widget identities already live in saved arrangements. Only the new activity surface
        // needs a suffix to avoid colliding with its feature's notices in the live host.
        return WidgetIdentifier(key.surface == .activity ? identifier + "/activity" : identifier)
    }
}
