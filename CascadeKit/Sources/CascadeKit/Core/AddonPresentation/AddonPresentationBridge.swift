//
//  AddonPresentationBridge.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import Foundation

/// AddonPresentationBridge converts validated, host-owned publication values
/// into native notch surfaces. It retains no provider, executor, filesystem
/// path, or transport object.
@MainActor
public final class AddonPresentationBridge {

    public typealias ActionHandler = @MainActor @Sendable (PublicationID, UInt64, ActionDescriptor) -> Void
    public typealias WidgetActionHandler = @MainActor @Sendable (PublicationID, UInt64, ActionDescriptor, AddonOptionsOrigin) -> Void
    public typealias OptionsActionHandler = @MainActor @Sendable (UUID, PublicationID, UInt64, ActionDescriptor) -> Void

    private struct Presented {

        let publication         : Publication
        let content             : PresentationSet
        let engineID            : String
        let widgetID            : WidgetIdentifier?
        let widget              : SnapshotWidget?
        let lease               : ActionLease
        let presentationRevision: UInt64
        let sessionStartedAt    : Date
    }

    private struct Pending {

        let presentationRevision: UInt64
        let sessionStartedAt    : Date
        let wasPresented        : Bool
    }

    private let sink         : any AddonPresentationSink
    private let assets       : any AddonPresentationAssetResolving
    private let now          : () -> Date
    private let actionHandler: ActionHandler
    private let widgetActionHandler: WidgetActionHandler?
    private let optionsActionHandler: OptionsActionHandler?

    private var optionsPresentation: AddonOptionsPresentation?
    private var optionsPage: SnapshotOptionsPage?
    private var optionsDismiss: (@MainActor () -> Void)?
    private var optionsExpiryTask: Task<Void, Never>?

    private var presented           : [PublicationID: Presented] = [:]
    private var pending             : [PublicationID: Pending] = [:]
    private var retired             : Set<PublicationID> = []
    private var retirementOverflowed = false

    public convenience init(
        engine  : NotchEngine,
        assets  : (any AddonPresentationAssetResolving)? = nil,
        onAction: @escaping ActionHandler = { _, _, _ in },
        onWidgetAction: WidgetActionHandler? = nil,
        onOptionsAction: OptionsActionHandler? = nil
    ) {
        self.init(
            sink    : engine,
            assets  : assets ?? EmptyAddonAssetResolver(),
            now     : Date.init,
            onAction: onAction,
            onWidgetAction: onWidgetAction,
            onOptionsAction: onOptionsAction
        )
    }

    init(
        sink    : any AddonPresentationSink,
        assets  : (any AddonPresentationAssetResolving)? = nil,
        now     : @escaping () -> Date = Date.init,
        onAction: @escaping ActionHandler = { _, _, _ in },
        onWidgetAction: WidgetActionHandler? = nil,
        onOptionsAction: OptionsActionHandler? = nil
    ) {
        self.sink     = sink
        self.assets   = assets ?? EmptyAddonAssetResolver()
        self.now      = now
        actionHandler = onAction
        widgetActionHandler = onWidgetAction
        optionsActionHandler = onOptionsAction
    }

    public func apply(_ publications: [Publication]) {
        let instant = now()
        var incoming: [PublicationID: Publication] = [:]
        for publication in publications where publication.expiresAt > instant {
            if incoming[publication.id].map({ $0.revision >= publication.revision }) == true { continue }
            incoming[publication.id] = publication
        }

        for id in Set(presented.keys).union(pending.keys).subtracting(incoming.keys) {
            retire(id)
        }
        if let optionsPresentation {
            let request = optionsPresentation.request
            if incoming[request.publicationID].flatMap({ resolvedContent(of: $0, at: instant) })?.widget?.privacy != .publicContent {
                dismissOptions(leaseID: request.leaseID)
            } else if incoming[request.publicationID]?.revision != request.observedRevision {
                invalidateOptionsControls(leaseID: request.leaseID)
            }
        }

        for publication in incoming.values.sorted(by: stableOrder) {
            let isKnown = presented[publication.id] != nil || pending[publication.id] != nil
            guard !retired.contains(publication.id), isKnown || !retirementOverflowed else { continue }
            guard let content = resolvedContent(of: publication, at: instant) else {
                holdPending(publication, at: instant)
                continue
            }

            if let old = presented[publication.id], old.publication == publication, old.content == content { continue }

            replace(
                publication,
                content     : content,
                previous    : presented[publication.id],
                pendingState: pending.removeValue(forKey: publication.id),
                at          : instant
            )
        }
    }

    private func replace(
        _ publication: Publication,
        content      : PresentationSet,
        previous     : Presented?,
        pendingState : Pending?,
        at instant   : Date
    ) {
        previous?.lease.revoke()

        let engineID = namespacedID(publication.id)
        let revision = (previous?.presentationRevision ?? pendingState?.presentationRevision ?? 0) &+ 1
        let start    = previous?.sessionStartedAt ?? pendingState?.sessionStartedAt ?? instant

        let lease = ActionLease(
            expiresAt: publication.expiresAt,
            now      : now
        ) { [publicationID = publication.id, wireRevision = publication.revision, actionHandler, widgetActionHandler, sink] action in
            if publication.kind == .widget,
               let widgetActionHandler,
               let origin = sink.captureOptionsOrigin(publicationID: publicationID, observedRevision: wireRevision) {
                widgetActionHandler(publicationID, wireRevision, action, origin)
            } else {
                actionHandler(publicationID, wireRevision, action)
            }
        }
        let resolver = ScopedAssetResolver(
            base               : assets,
            publicationID      : publication.id,
            publicationRevision: publication.revision
        )

        var widgetID      : WidgetIdentifier?
        var snapshotWidget: SnapshotWidget?
        switch publication.kind {
            case .widget:
                guard let document = content.widget else { return }

                if let widget = previous?.widget {
                    widget.update(
                        document: document,
                        assets  : resolver,
                        actions : lease,
                        observedRevision: publication.revision
                    )
                    widgetID       = widget.id
                    snapshotWidget = widget
                } else {
                    let widget = SnapshotWidget(
                        id      : engineID,
                        document: document,
                        assets  : resolver,
                        actions : lease,
                        observedRevision: publication.revision
                    )
                    widgetID       = widget.id
                    snapshotWidget = widget
                    sink.register(widget)
                }

            case .activity:
                let lifetime = NotchActivityLifetime(
                    startedAt: start,
                    duration : max(0, publication.expiresAt.timeIntervalSince(start))
                )
                sink.present(SnapshotActivity(
                    id      : engineID,
                    sourceID: "addon:\(publication.id.addonID.rawValue)",
                    revision: revision,
                    content : content,
                    lifetime: lifetime,
                    assets  : resolver,
                    actions : lease
                ))

            case .notice:
                let notice = SnapshotNotice(
                    id      : engineID,
                    sourceID: "addon:\(publication.id.addonID.rawValue)",
                    revision: revision,
                    content : content,
                    assets  : resolver,
                    actions : lease
                )
                if previous == nil && pendingState?.wasPresented != true {
                    sink.showNotice(notice)
                } else {
                    sink.updateNotice(notice)
                }
        }

        presented[publication.id] = Presented(
            publication         : publication,
            content             : content,
            engineID            : engineID,
            widgetID            : widgetID,
            widget              : snapshotWidget,
            lease               : lease,
            presentationRevision: revision,
            sessionStartedAt    : start
        )
    }

    private func retire(_ id: PublicationID) {
        let old     = presented.removeValue(forKey: id)
        let waiting = pending.removeValue(forKey: id)
        guard old != nil || waiting != nil else { return }

        old?.lease.revoke()
        if let widgetID = old?.widgetID {
            sink.unregisterWidget(id: widgetID)
        } else if let engineID = old?.engineID {
            sink.dismissActivity(id: engineID)
        }

        if retired.count < 4096 {
            retired.insert(id)
        } else {
            retirementOverflowed = true
        }
    }

    private func holdPending(
        _ publication: Publication,
        at instant   : Date
    ) {
        let old     = presented.removeValue(forKey: publication.id)
        let waiting = pending[publication.id]

        old?.lease.revoke()
        if let widgetID = old?.widgetID {
            sink.unregisterWidget(id: widgetID)
        } else if let engineID = old?.engineID {
            sink.dismissActivity(id: engineID)
        }

        pending[publication.id] = Pending(
            presentationRevision: old?.presentationRevision ?? waiting?.presentationRevision ?? 0,
            sessionStartedAt    : old?.sessionStartedAt ?? waiting?.sessionStartedAt ?? instant,
            wasPresented        : old != nil || waiting?.wasPresented == true
        )
    }

    /// presentOptions rechecks the source and opaque origin after an actor hop. This
    /// common presenter also serves host-owned Debug fixtures without provider code.
    @discardableResult
    public func presentOptions(
        _ presentation: AddonOptionsPresentation,
        onDismiss     : @escaping @MainActor () -> Void
    ) -> Bool {
        let request = presentation.request
        guard presentation.origin.isValid,
              presentation.expiresAt > now(),
              let source = presented[request.publicationID],
              source.publication.kind == .widget,
              source.publication.revision == request.observedRevision,
              source.publication.expiresAt >= presentation.expiresAt,
              (try? request.validate()) != nil
        else { return false }
        if let current = optionsPresentation, current.request.leaseID == request.leaseID {
            guard current.origin === presentation.origin,
                  current.generation == presentation.generation,
                  current.request.actionRequestID == request.actionRequestID,
                  presentation.expiresAt <= current.expiresAt
            else { return false }
        } else if let current = optionsPresentation, current.origin === presentation.origin {
            return false
        }
        let actions = ActionLease(expiresAt: presentation.expiresAt, now: now) {
            [weak self, origin = presentation.origin] action in
            guard origin.isValid,
                  self?.optionsPresentation?.request.leaseID == request.leaseID
            else { return }
            self?.optionsActionHandler?(request.leaseID, request.publicationID, request.observedRevision, action)
        }
        let page = SnapshotOptionsPage(
            id      : "options:\(request.leaseID.uuidString)",
            document: request.document,
            assets  : ScopedAssetResolver(base: assets, publicationID: request.publicationID, publicationRevision: request.observedRevision),
            actions : actions,
            revision: (optionsPage?.contentRevision ?? 0) &+ 1
        )
        guard sink.presentOptions(page: page, leaseID: request.leaseID, origin: presentation.origin, onDismiss: { [weak self, origin = presentation.origin] in
            guard self?.optionsPresentation?.origin === origin else { return }
            self?.finishOptionsDismissal(leaseID: request.leaseID)
        }) else {
            actions.revoke()
            return false
        }
        optionsPage?.actions.revoke()
        optionsExpiryTask?.cancel()
        optionsPresentation = presentation
        optionsPage = page
        optionsDismiss = onDismiss
        let duration = max(0, presentation.expiresAt.timeIntervalSince(now()))
        optionsExpiryTask = Task { [weak self, origin = presentation.origin] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard self?.optionsPresentation?.origin === origin else { return }
            self?.dismissOptions(leaseID: request.leaseID)
        }
        return true
    }

    public func invalidateOptionsControls(leaseID: UUID, origin: AddonOptionsOrigin? = nil) {
        guard let presentation = optionsPresentation,
              presentation.request.leaseID == leaseID,
              origin == nil || presentation.origin === origin,
              let optionsPage
        else { return }
        optionsPage.invalidateControls()
        _ = sink.presentOptions(page: optionsPage, leaseID: leaseID, origin: presentation.origin, onDismiss: { [weak self, origin = presentation.origin] in
            guard self?.optionsPresentation?.origin === origin else { return }
            self?.finishOptionsDismissal(leaseID: leaseID)
        })
    }

    public func dismissOptions(leaseID: UUID, origin: AddonOptionsOrigin? = nil) {
        guard optionsPresentation?.request.leaseID == leaseID,
              origin == nil || optionsPresentation?.origin === origin
        else { return }
        finishOptionsDismissal(leaseID: leaseID)
        sink.dismissOptions(leaseID: leaseID)
    }

    private func finishOptionsDismissal(leaseID: UUID) {
        guard optionsPresentation?.request.leaseID == leaseID else { return }
        optionsPresentation?.origin.revoke()
        optionsPage?.actions.revoke()
        optionsExpiryTask?.cancel()
        optionsExpiryTask = nil
        optionsPage = nil
        optionsPresentation = nil
        let callback = optionsDismiss
        optionsDismiss = nil
        callback?()
    }

    private func resolvedContent(
        of publication: Publication,
        at date       : Date
    ) -> PresentationSet? {
        if let content = publication.content { return content }

        return publication.timeline?.last { $0.date <= date }?.content
    }

    private func namespacedID(_ id: PublicationID) -> String {
        "addon:\(id.addonID.rawValue):\(id.sessionID.uuidString):\(id.instanceID.uuidString)"
    }

    private func stableOrder(
        _ lhs: Publication,
        _ rhs: Publication
    ) -> Bool {
        namespacedID(lhs.id) < namespacedID(rhs.id)
    }
}
