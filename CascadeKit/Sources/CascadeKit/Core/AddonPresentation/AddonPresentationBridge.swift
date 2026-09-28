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

    private struct Presented {
        let publication: Publication
        let content: PresentationSet
        let engineID: String
        let widgetID: WidgetIdentifier?
        let widget: SnapshotWidget?
        let lease: ActionLease
        let presentationRevision: UInt64
        let sessionStartedAt: Date
    }

    private struct Pending {
        let presentationRevision: UInt64
        let sessionStartedAt: Date
        let wasPresented: Bool
    }

    private let sink: any AddonPresentationSink
    private let assets: any AddonPresentationAssetResolving
    private let now: () -> Date
    private let actionHandler: ActionHandler
    private var presented: [PublicationID: Presented] = [:]
    private var pending: [PublicationID: Pending] = [:]
    private var retired: Set<PublicationID> = []
    private var retirementOverflowed = false

    public convenience init(
        engine: NotchEngine,
        assets: (any AddonPresentationAssetResolving)? = nil,
        onAction: @escaping ActionHandler = { _, _, _ in }
    ) {
        self.init(sink: engine, assets: assets ?? EmptyAddonAssetResolver(), now: Date.init, onAction: onAction)
    }

    init(
        sink: any AddonPresentationSink,
        assets: (any AddonPresentationAssetResolving)? = nil,
        now: @escaping () -> Date = Date.init,
        onAction: @escaping ActionHandler = { _, _, _ in }
    ) {
        self.sink = sink; self.assets = assets ?? EmptyAddonAssetResolver(); self.now = now; actionHandler = onAction
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

        for publication in incoming.values.sorted(by: stableOrder) {
            let isKnown = presented[publication.id] != nil || pending[publication.id] != nil
            guard !retired.contains(publication.id), isKnown || !retirementOverflowed else { continue }
            guard let content = resolvedContent(of: publication, at: instant) else {
                holdPending(publication, at: instant)
                continue
            }
            if let old = presented[publication.id], old.publication == publication, old.content == content { continue }
            replace(publication, content: content, previous: presented[publication.id], pendingState: pending.removeValue(forKey: publication.id), at: instant)
        }
    }

    private func replace(_ publication: Publication, content: PresentationSet, previous: Presented?, pendingState: Pending?, at instant: Date) {
        previous?.lease.revoke()
        let engineID = namespacedID(publication.id)
        let revision = (previous?.presentationRevision ?? pendingState?.presentationRevision ?? 0) &+ 1
        let start = previous?.sessionStartedAt ?? pendingState?.sessionStartedAt ?? instant
        let lease = ActionLease(expiresAt: publication.expiresAt, now: now) { [publicationID = publication.id, wireRevision = publication.revision, actionHandler] action in
            actionHandler(publicationID, wireRevision, action)
        }
        let resolver = ScopedAssetResolver(
            base               : assets,
            publicationID      : publication.id,
            publicationRevision: publication.revision
        )
        var widgetID: WidgetIdentifier?
        var snapshotWidget: SnapshotWidget?
        switch publication.kind {
        case .widget:
            guard let document = content.widget else { return }
            if let widget = previous?.widget {
                widget.update(document: document, assets: resolver, actions: lease)
                widgetID = widget.id; snapshotWidget = widget
            } else {
                let widget = SnapshotWidget(id: engineID, document: document, assets: resolver, actions: lease)
                widgetID = widget.id; snapshotWidget = widget
                sink.register(widget)
            }
        case .activity:
            let lifetime = NotchActivityLifetime(
                startedAt: start,
                duration: max(0, publication.expiresAt.timeIntervalSince(start))
            )
            sink.present(SnapshotActivity(id: engineID, sourceID: "addon:\(publication.id.addonID.rawValue)", revision: revision, content: content, lifetime: lifetime, assets: resolver, actions: lease))
        case .notice:
            let notice = SnapshotNotice(id: engineID, sourceID: "addon:\(publication.id.addonID.rawValue)", revision: revision, content: content, assets: resolver, actions: lease)
            if previous == nil && pendingState?.wasPresented != true { sink.showNotice(notice) }
            else { sink.updateNotice(notice) }
        }
        presented[publication.id] = Presented(publication: publication, content: content, engineID: engineID, widgetID: widgetID, widget: snapshotWidget, lease: lease, presentationRevision: revision, sessionStartedAt: start)
    }

    private func retire(_ id: PublicationID) {
        let old = presented.removeValue(forKey: id)
        let waiting = pending.removeValue(forKey: id)
        guard old != nil || waiting != nil else { return }
        old?.lease.revoke()
        if let widgetID = old?.widgetID { sink.unregisterWidget(id: widgetID) }
        else if let engineID = old?.engineID { sink.dismissActivity(id: engineID) }
        if retired.count < 4096 { retired.insert(id) } else { retirementOverflowed = true }
    }

    private func holdPending(_ publication: Publication, at instant: Date) {
        let old = presented.removeValue(forKey: publication.id)
        let waiting = pending[publication.id]
        old?.lease.revoke()
        if let widgetID = old?.widgetID { sink.unregisterWidget(id: widgetID) }
        else if let engineID = old?.engineID { sink.dismissActivity(id: engineID) }
        pending[publication.id] = Pending(
            presentationRevision: old?.presentationRevision ?? waiting?.presentationRevision ?? 0,
            sessionStartedAt: old?.sessionStartedAt ?? waiting?.sessionStartedAt ?? instant,
            wasPresented: old != nil || waiting?.wasPresented == true
        )
    }

    private func resolvedContent(of publication: Publication, at date: Date) -> PresentationSet? {
        if let content = publication.content { return content }
        return publication.timeline?.last { $0.date <= date }?.content
    }

    private func namespacedID(_ id: PublicationID) -> String {
        "addon:\(id.addonID.rawValue):\(id.sessionID.uuidString):\(id.instanceID.uuidString)"
    }

    private func stableOrder(_ lhs: Publication, _ rhs: Publication) -> Bool {
        namespacedID(lhs.id) < namespacedID(rhs.id)
    }
}
