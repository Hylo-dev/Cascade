//
//  PluginSurfaceRouter.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginEngine
import Foundation

/// PluginAcceptedAction runs once the broker accepted a control: it rechecks the page's
/// authority on main and only then invokes the native effect, which cannot escape that
/// synchronous boundary.
public typealias PluginAcceptedAction = @MainActor @Sendable (_ nativeEffect: @MainActor () -> Void) -> Void

/// PluginSurfaceRouter puts plugin publications where they belong on the notch, as the spec's
/// publication sink does: one store per publication, and for a widget one `PluginWidget` on the
/// grid, registered with its first content and removed with its withdrawal. Later publications
/// only update the store. A notice gets one store and one `PluginNotice`, shown again for every
/// publication, or only enriched in place when the publication asks to update, and dismissed with
/// its withdrawal. An activity gets one store and one `PluginActivity`, presented with its first
/// content and kept in place by later ones. A change of its attributes is presented again, so the
/// host sees the new relevance; a renewed start ends the old session first and presents it
/// anew, because the host keeps an existing session's deadline and only a new session gets a
/// fresh eight hours. It is ended with its withdrawal. An activity's controls submit through the
/// same broker as a widget's, with no options origin: only a widget's options page has one.
///
/// A detail publication gets one store and one `PluginDetail`, kept but not shown: the widget of
/// the same feature opens it, and its withdrawal closes it.
///
/// A widget whose feature supports fullscreen may also publish an options page. Pressing an
/// opener captures a host-owned origin first, then asks the broker; only the accepted click
/// presents the page, and only the page's own controls, holding that origin, can act in it.
///
/// Which plugins' widgets a display nobody edited places by default is the app's policy, handed
/// in as `placedByDefault`; every other plugin's widget waits in the gallery.
@MainActor
public final class PluginSurfaceRouter {

    /// components lists the tier-2 components these surfaces draw, for the engine's capabilities.
    public static let components: Set<String> = PluginComponentView.identifiers

    private let host           : any PluginSurfaceHosting
    private let sizes          : [PluginPublicationKey: [GridSpan]]
    private let placedByDefault: Set<PluginID>
    private let services       : PluginComponentServices
    private let hasDetail      : Set<PluginPublicationKey>
    private let submit         : (PluginActionRequest) -> Void
    private let visibility     : (Bool, PluginPublicationKey) -> Void
    private let submitAccepted : ((PluginActionRequest, @escaping PluginAcceptedAction) -> Void)?
    private let fullscreen     : Set<PluginPublicationKey>
    private var options        : OptionsBinding?

    private struct OptionsBinding {

        let key    : PluginPublicationKey
        let origin : PluginOptionsOrigin
        let store  : PluginNodeStore
        let leaseID: UUID
        let page   : PluginOptionsPage
        var isPresented = false
    }

    private var stores     : [PluginPublicationKey: PluginNodeStore] = [:]
    private var notices    : [PluginPublicationKey: PluginNotice] = [:]
    private var activities : [PluginPublicationKey: PluginActivity] = [:]
    private var details    : [PluginPublicationKey: PluginDetail] = [:]
    private var openDetails: Set<PluginPublicationKey> = []

    public init(
        host           : any PluginSurfaceHosting,
        manifests      : [PluginManifest],
        placedByDefault: Set<PluginID>,
        services       : PluginComponentServices? = nil,
        submit         : @escaping (PluginActionRequest) -> Void,
        visibility     : @escaping (Bool, PluginPublicationKey) -> Void,
        submitAccepted : ((PluginActionRequest, @escaping PluginAcceptedAction) -> Void)? = nil
    ) {
        self.host            = host
        self.placedByDefault = placedByDefault
        self.services        = services ?? PluginComponentServices()
        self.submit          = submit
        self.visibility      = visibility
        self.submitAccepted  = submitAccepted

        var sizes     : [PluginPublicationKey: [GridSpan]] = [:]
        var hasDetail : Set<PluginPublicationKey> = []
        var fullscreen: Set<PluginPublicationKey> = []
        for manifest in manifests {
            for feature in manifest.features {
                if feature.surfaces.detail != nil {
                    hasDetail.insert(PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .detail))
                }
                if let declared = feature.surfaces.widget?.sizes {
                    sizes[PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget)] = declared.map(GridSpan.init)
                    if feature.supportsFullscreen {
                        fullscreen.insert(PluginPublicationKey(plugin: manifest.id, feature: feature.id, surface: .widget))
                    }
                }
            }
        }
        self.sizes      = sizes
        self.hasDetail  = hasDetail
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
            if options?.key == change.key { clearOptions() }
            if stores.removeValue(forKey: change.key) != nil {
                host.unregisterWidget(id: Self.identifier(of: change.key))
            }
        } else if let store = stores[change.key] {
            store.apply(change)
            // A pending click survives a publication that still offers options: the broker
            // accepted it against the revision the user saw, and the page then shows the newest
            // content, which reaches it through the store without presenting it again. Only a
            // publication that withdraws the options ends the page or the pending click.
            if let binding = options, binding.key == change.key,
               store.optionsRoot == nil || !binding.origin.isValid {
                clearOptions()
            }
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
    /// reports it hidden through `onDismiss`, exactly once, however it ends. Between the two, the
    /// notch closing and reopening over the kept detail reports it hidden and visible again
    /// (`onPresented`), so its plugin is never believed on screen behind a closed notch and gets
    /// its one refresh for stale content when the page comes back. A host that refuses
    /// the show never calls `onDismiss`, so nothing is tracked or reported then. Without a detail
    /// publication yet there is nothing to open.
    private func open(detail key: PluginPublicationKey) {
        guard let detail = details[key] else { return }

        let isShown = host.showDetail(
            detail,
            on       : nil,
            onDismiss  : { [weak self, visibility] in
                self?.openDetails.remove(key)
                visibility(false, key)
            },
            onPresented: { [visibility] isPresented in
                visibility(isPresented, key)
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

    /// route presents an activity with its first content, updates it in place after, and ends it
    /// with its withdrawal. The host reads the content through the store, so a content update
    /// calls it for nothing. Attributes the host snapshots, such as relevance, are presented
    /// again; a renewed start is ended and then presented, since the host's entry would keep the
    /// old session's deadline and the cap would end the activity early.
    private func route(activity change: PluginPublicationChange) {
        let key = change.key
        guard let content = change.content else {
            stores[key] = nil
            if activities.removeValue(forKey: key) != nil {
                host.endActivity(id: Self.identifier(of: key).rawValue)
            }
            return
        }
        guard let attributes = content.activity else { return }

        let store = stores[key] ?? PluginNodeStore(key: key, submit: submit)
        stores[key] = store
        store.apply(change)

        if let activity = activities[key] {
            let previous = activity.attributes
            activity.update(attributes)
            if previous.startedAt != attributes.startedAt {
                host.endActivity(id: activity.id)
                host.present(activity)
            } else if previous != attributes {
                host.present(activity)
            }
            return
        }

        let activity = PluginActivity(
            id        : Self.identifier(of: key).rawValue,
            sourceID  : key.plugin.rawValue,
            store     : store,
            attributes: attributes,
            visibility: { [visibility] isVisible in visibility(isVisible, key) }
        )
        activities[key] = activity
        host.present(activity)
    }

    /// place makes the store for a widget's first content, fills it, then registers the widget,
    /// so the grid never shows an empty tile.
    private func place(_ change: PluginPublicationChange) {
        let key   = change.key
        let store = PluginNodeStore(
            key          : key,
            submit       : { [weak self] request in self?.submitWidget(request) },
            submitOptions: { [weak self] request, origin in self?.submitOptions(request, origin: origin) }
        )
        store.apply(change)
        stores[key] = store

        let detailKey = PluginPublicationKey(plugin: key.plugin, feature: key.feature, surface: .detail)
        var openDetail: (@MainActor () -> Void)?
        if hasDetail.contains(detailKey) {
            openDetail = { [weak self] in self?.open(detail: detailKey) }
        }

        host.register(
            PluginWidget(
                id                : Self.identifier(of: key),
                sizes             : sizes[key] ?? [],
                isPlacedByDefault : placedByDefault.contains(key.plugin),
                store             : store,
                services          : services,
                openDetail        : openDetail,
                visibility        : { [visibility] isVisible in visibility(isVisible, key) },
                supportsFullscreen: fullscreen.contains(key)
            )
        )
    }

    /// submitWidget sends a widget's control, except an options opener, which first captures
    /// the mounted origin before the broker hop. Its acceptance closure holds that exact click,
    /// so an equal late request cannot open the page.
    private func submitWidget(_ request: PluginActionRequest) {
        guard let store = stores[request.key], store.revision == request.revision else { return }
        guard !store.isOptionsNode(request.node) else { return }
        guard store.isOptionsButton(request.node) else {
            submit(request)
            return
        }
        guard fullscreen.contains(request.key), let submitAccepted,
              let origin = host.captureOptionsOrigin(
                  widgetID        : Self.identifier(of: request.key),
                  observedRevision: request.revision
              )
        else { return }

        clearOptions()
        let binding = OptionsBinding(
            key    : request.key,
            origin : origin,
            store  : store,
            leaseID: UUID(),
            page   : PluginOptionsPage(
                id    : Self.identifier(of: request.key).rawValue + "/options",
                store : store,
                origin: origin
            )
        )
        options = binding
        submitAccepted(request) { [weak self, origin] nativeEffect in
            guard self?.acceptOptions(origin) == true, origin.isValid else { return }
            nativeEffect()
        }
    }

    /// submitOptions carries the control's own origin through acceptance. Equal-valued
    /// requests from later pages cannot authorize this effect, even over the same live store.
    private func submitOptions(
        _ request: PluginActionRequest,
        origin   : PluginOptionsOrigin
    ) {
        guard let submitAccepted, isCurrentOptions(request, origin: origin) else { return }
        submitAccepted(request) { [weak self, origin] nativeEffect in
            guard self?.isCurrentOptions(request, origin: origin) == true else { return }
            nativeEffect()
        }
    }

    private func isCurrentOptions(
        _ request: PluginActionRequest,
        origin   : PluginOptionsOrigin
    ) -> Bool {
        guard let binding = options,
              binding.origin === origin,
              origin.isValid,
              binding.key == request.key,
              binding.isPresented,
              stores[request.key] === binding.store,
              binding.store.revision == request.revision,
              binding.store.isOptionsNode(request.node)
        else { return false }
        return true
    }

    private func acceptOptions(_ origin: PluginOptionsOrigin) -> Bool {
        guard var binding = options, binding.origin === origin, origin.isValid,
              stores[binding.key] === binding.store,
              binding.store.revision >= origin.observedRevision,
              binding.store.optionsRoot != nil
        else { return false }
        let isPresented = host.presentOptions(
            page     : binding.page,
            leaseID  : binding.leaseID,
            origin   : origin,
            onDismiss: { [weak self, origin] in self?.didDismiss(origin) }
        )
        guard isPresented else {
            clearOptions()
            return false
        }

        binding.isPresented = true
        options = binding
        return true
    }

    private func didDismiss(_ origin: PluginOptionsOrigin) {
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
        WidgetIdentifier("plugin:" + key.plugin.rawValue + "/" + key.feature)
    }
}
