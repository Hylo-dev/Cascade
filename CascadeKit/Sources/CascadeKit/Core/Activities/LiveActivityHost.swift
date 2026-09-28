//
//  LiveActivityHost.swift
//  CascadeKit
//

import Foundation

/// ActivitySelection describes the shared live registry independently from any
/// one display. Compact choices survive notice overrides and expanded ownership.
struct ActivitySelection {
    let primary  : (any NotchLiveActivity)?
    let secondary: (any NotchLiveActivity)?
    let expanded : (any NotchLiveActivity)?
    let notice   : (any NotchTransientNotice)?
}

/// ActivityExpansionSelection distinguishes a closed surface, one requested
/// live activity, explicit fallback content, and a widget-only opening.
enum ActivityExpansionSelection: Equatable {
    case none
    case activity(String)
    case fallback
    case widgets
}

/// VisibleActivityProjection reports which exact provider instances remain
/// eligible after applying the coordinator's complete retained-root union.
struct VisibleActivityProjection {
    let accepted: [any NotchActivity]
    let rejected: [any NotchActivity]
}

/// LiveActivityHost arbitrates finite live sessions and bounded status notices.
/// Selection is shared state; activation follows the instance-aware union of
/// roots that displays actually retain. One scheduler owns every deadline.
@MainActor
final class LiveActivityHost {
    var onChange: (() -> Void)?
    /// onValidityChange reports terminal retained-root invalidation even when
    /// compact and expanded selection remain unchanged.
    var onValidityChange: (() -> Void)?

    private(set) var selection = ActivitySelection(
        primary  : nil,
        secondary: nil,
        expanded : nil,
        notice   : nil
    )

    var pendingNoticeCount: Int { notices.count }
    /// presentationValidityRevision advances once per terminal invalidation
    /// transaction so a coordinator can coalesce redundant callbacks.
    private(set) var presentationValidityRevision: UInt64 = 0
    /// retainedOutgoingActivityCount exposes the bounded replacement handoff
    /// state to internal verification.
    var retainedOutgoingActivityCount: Int { retainedOutgoingActivities.count }

    private struct LiveEntry {
        let activity: any NotchLiveActivity
        var revision: UInt64
        var lifetime: NotchActivityLifetime
        var relevance: Double
        let order: UInt64
        let sessionDeadline: Date

        var expiresAt: Date { min(lifetime.expiresAt, sessionDeadline) }
    }

    private struct Notice {
        let activity: any NotchTransientNotice
        var revision: UInt64
        let expires: Date
    }

    private struct Activation {
        let activity: any NotchActivity
        let context: LiveActivityContext
    }

    private struct ContentKey: Equatable {
        let identity: ObjectIdentifier
        let revision: UInt64
        let isStale: Bool
    }

    private struct SelectionKey: Equatable {
        let primary  : ContentKey?
        let secondary: ContentKey?
        let expanded : ContentKey?
        let notice   : ContentKey?
        let expansion: ActivityExpansionSelection
    }

    private var persistent: [LiveEntry] = []
    private var notices: [Notice] = []
    private var activations: [ObjectIdentifier: Activation] = [:]
    private var desiredVisibleActivities: [ObjectIdentifier: any NotchActivity] = [:]
    private var retainedOutgoingActivities: [ObjectIdentifier: any NotchActivity] = [:]
    private var selectionKey = SelectionKey(
        primary  : nil,
        secondary: nil,
        expanded : nil,
        notice   : nil,
        expansion: .none
    )
    private(set) var expansionSelection: ActivityExpansionSelection = .none
    private var expandedFallback: (any NotchLiveActivity)?
    private var isVisible = false
    private var nextOrder: UInt64 = 0
    private var deadlineTask: Task<Void, Never>?
    private var scheduledDeadline: Date?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    /// setExpandedFallback registers widget-like expanded content without adding
    /// it to compact ranking or the live-session deadline scheduler.
    func setExpandedFallback(_ activity: (any NotchLiveActivity)?) {
        let outgoing = expandedFallback
        expandedFallback = activity
        if let outgoing, let activity, outgoing !== activity {
            retainOutgoingIfPresented(outgoing)
        }
        reconcileSelection()
    }

    func present(_ activity: any NotchLiveActivity) {
        expireNotices()
        let lifetime = activity.lifetime
        guard !lifetime.hasEnded(at: now()) else {
            end(id: activity.id)
            return
        }
        let relevance = normalizedRelevance(activity.relevanceScore)
        if let index = persistent.firstIndex(where: { $0.activity.id == activity.id }) {
            let old = persistent[index]
            guard old.activity !== activity || old.revision != activity.contentRevision
                    || old.lifetime != lifetime || old.relevance != relevance else { return }
            if old.activity !== activity { retainOutgoingIfPresented(old.activity) }
            persistent[index] = LiveEntry(
                activity       : activity,
                revision       : activity.contentRevision,
                lifetime       : lifetime,
                relevance      : relevance,
                order          : old.order,
                sessionDeadline: old.sessionDeadline
            )
        } else {
            nextOrder &+= 1
            persistent.append(
                LiveEntry(
                    activity       : activity,
                    revision       : activity.contentRevision,
                    lifetime       : lifetime,
                    relevance      : relevance,
                    order          : nextOrder,
                    sessionDeadline: min(lifetime.startedAt, now())
                        .addingTimeInterval(NotchActivityLifetime.maximumDuration)
                )
            )
        }
        notices.removeAll { $0.activity.id == activity.id }
        expireNotices()
    }

    func showNotice(_ notice: any NotchTransientNotice) {
        guard expansionSelection == .none else { return }
        expireNotices()
        let duration = notice.displayDuration
        guard duration.isFinite, duration > 0 else { return }
        let entry = Notice(
            activity: notice,
            revision: notice.contentRevision,
            expires : now().addingTimeInterval(min(duration, 10))
        )
        if let index = notices.firstIndex(where: { $0.activity.id == notice.id }) {
            let old = notices[index]
            guard old.activity !== notice || old.revision != notice.contentRevision else { return }
            if old.activity !== notice { retainOutgoingIfPresented(old.activity) }
            notices.remove(at: index)
            notices.append(entry)
        } else {
            if notices.count == 8 { notices.removeFirst() }
            notices.append(entry)
        }
        persistent.removeAll { $0.activity.id == notice.id }
        expireNotices()
    }

    /// updateNotice enriches a pending event without changing its position or
    /// deadline. A dismissed event cannot be recreated by a late result.
    func updateNotice(_ notice: any NotchTransientNotice) {
        guard expansionSelection == .none else { return }
        expireNotices()
        guard let index = notices.firstIndex(where: {
            $0.activity.id == notice.id && $0.activity.sourceID == notice.sourceID
        }), notice.contentRevision > notices[index].revision else { return }
        if notices[index].activity !== notice {
            retainOutgoingIfPresented(notices[index].activity)
        }
        notices[index] = Notice(
            activity: notice,
            revision: notice.contentRevision,
            expires : notices[index].expires
        )
        reconcileSelection()
    }

    /// end removes a live session even while an outgoing view instance is held
    /// for animation. The coordinator releases that retained root separately.
    func end(id: String) {
        guard persistent.contains(where: { $0.activity.id == id }) else { return }
        dismiss(id: id)
    }

    func dismiss(id: String) {
        let removedLive = persistent
            .filter { $0.activity.id == id }
            .map(\.activity)
        persistent.removeAll { $0.activity.id == id }
        notices.removeAll { $0.activity.id == id }
        var preservedFallbackIdentity: ObjectIdentifier?
        if case .activity(id) = expansionSelection,
           let fallback = expandedFallback,
           removedLive.contains(where: { $0 === fallback }) {
            expansionSelection = .fallback
            preservedFallbackIdentity = ObjectIdentifier(fallback)
        } else if expansionSelection == .fallback, let fallback = expandedFallback {
            preservedFallbackIdentity = ObjectIdentifier(fallback)
        }
        revokeRetainedActivities(
            where     : { $0.id == id },
            preserving: preservedFallbackIdentity
        )
        reconcileSelection()
        scheduleExpiration()
    }

    func dismissActivities(from sourceID: String) {
        persistent.removeAll { $0.activity.sourceID == sourceID }
        notices.removeAll { $0.activity.sourceID == sourceID }
        if expandedFallback?.sourceID == sourceID { expandedFallback = nil }
        revokeRetainedActivities { $0.sourceID == sourceID }
        reconcileSelection()
        scheduleExpiration()
    }

    /// setExpansion selects expanded content without changing compact ranking.
    /// `.fallback` is deliberately explicit so a widget-only opening never
    /// reveals a globally registered activity by accident.
    func setExpansion(_ expansion: ActivityExpansionSelection) {
        guard expansionSelection != expansion else { return }
        expansionSelection = expansion
        if expansion != .none {
            notices.removeAll()
            revokeRetainedActivities { $0 is any NotchTransientNotice }
        }
        reconcileSelection()
        scheduleExpiration()
    }

    /// setVisibleActivities reconciles actual roots by object identity and
    /// returns explicit evidence for roots invalidated by a terminal event.
    /// Omitting a valid outgoing replacement acknowledges the cleared root and
    /// releases its eligibility; later replay is rejected unless republished.
    @discardableResult
    func setVisibleActivities(
        _ activities: [any NotchActivity]
    ) -> VisibleActivityProjection {
        let submittedIdentities = Set(activities.map(ObjectIdentifier.init))
        retainedOutgoingActivities = retainedOutgoingActivities.filter {
            submittedIdentities.contains($0.key)
        }

        var desired: [ObjectIdentifier: any NotchActivity] = [:]
        var accepted: [any NotchActivity] = []
        var rejected: [any NotchActivity] = []
        var seen: Set<ObjectIdentifier> = []
        for activity in activities {
            let identity = ObjectIdentifier(activity)
            guard seen.insert(identity).inserted else { continue }
            if !isRegistered(activity), retainedOutgoingActivities[identity] == nil {
                rejected.append(activity)
                continue
            }
            desired[identity] = activity
            accepted.append(activity)
        }
        if desired.keys != desiredVisibleActivities.keys {
            desiredVisibleActivities = desired
            reconcileActivations()
        }
        return VisibleActivityProjection(accepted: accepted, rejected: rejected)
    }

    /// isPresentationValid lets the coordinator test retained roots immediately
    /// after onValidityChange, even when ActivitySelection itself did not move.
    func isPresentationValid(_ activity: any NotchActivity) -> Bool {
        isRegistered(activity)
            || retainedOutgoingActivities[ObjectIdentifier(activity)] != nil
    }

    /// setVisible gates the whole session for lock/suspension. The desired
    /// instance union survives so unlock can reactivate it once.
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if !visible {
            notices.removeAll()
            revokeRetainedActivities { $0 is any NotchTransientNotice }
            expansionSelection = .none
            reconcileSelection()
        }
        reconcileActivations()
    }

    func isStale(_ activity: any NotchActivity) -> Bool {
        persistent.first {
            $0.activity === activity
        }?.lifetime.isStale(at: now()) ?? false
    }

    /// expireNotices performs one-shot deadline reconciliation. Expiration
    /// updates every selection field immediately and never resurrects a handle.
    func expireNotices() {
        let instant = now()
        let expiredLive = persistent
            .filter { $0.expiresAt <= instant }
            .map(\.activity)
        let expiredNotices = notices
            .filter { $0.expires <= instant }
            .map(\.activity)
        persistent.removeAll { $0.expiresAt <= instant }
        notices.removeAll { $0.expires <= instant }
        if case let .activity(id) = expansionSelection,
           expiredLive.contains(where: { $0.id == id }),
           let fallback = expandedFallback,
           expiredLive.contains(where: { $0 === fallback }) {
            expansionSelection = .fallback
        }
        let expiredLiveIDs = Set(expiredLive.map(\.id))
        let expiredNoticeIDs = Set(expiredNotices.map(\.id))
        let preservedFallbackIdentity = expansionSelection == .fallback
            ? expandedFallback.map(ObjectIdentifier.init)
            : nil
        revokeRetainedActivities(
            where: { activity in
                if activity is any NotchTransientNotice {
                    return expiredNoticeIDs.contains(activity.id)
                }
                return expiredLiveIDs.contains(activity.id)
            },
            preserving: preservedFallbackIdentity
        )
        reconcileSelection()
        scheduleExpiration()
    }

    func stop() {
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadline = nil
        persistent.removeAll()
        notices.removeAll()
        expandedFallback = nil
        expansionSelection = .none
        desiredVisibleActivities.removeAll()
        retainedOutgoingActivities.removeAll()
        isVisible = false
        reconcileSelection()
        reconcileActivations()
    }

    /// reconcileSelection computes shared content only. Activation is driven by
    /// setVisibleActivities after the coordinator has projected all displays.
    private func reconcileSelection() {
        var compact: [any NotchLiveActivity] = []
        for entry in rankedLiveEntries
            where !compact.contains(where: { $0.sourceID == entry.activity.sourceID }) {
            compact.append(entry.activity)
            if compact.count == 2 { break }
        }

        let expanded: (any NotchLiveActivity)?
        switch expansionSelection {
        case .none:
            expanded = nil
        case let .activity(id):
            expanded = persistent.first { $0.activity.id == id }?.activity
        case .fallback:
            expanded = expandedFallback
        case .widgets:
            expanded = nil
        }

        let next = ActivitySelection(
            primary  : compact.first,
            secondary: compact.dropFirst().first,
            expanded : expanded,
            notice   : notices.last?.activity
        )
        let nextKey = SelectionKey(
            primary  : key(for: next.primary),
            secondary: key(for: next.secondary),
            expanded : key(for: next.expanded),
            notice   : key(for: next.notice),
            expansion: expansionSelection
        )
        selection = next
        guard nextKey != selectionKey else { return }
        selectionKey = nextKey
        onChange?()
    }

    /// reconcileActivations acquires each provider once per object instance.
    /// Contexts are installed before activate so synchronous invalidation is safe.
    private func reconcileActivations() {
        let desired = isVisible
            ? desiredVisibleActivities
            : [:]

        for (identity, activation) in activations where desired[identity] == nil {
            activation.context.revoke()
            activations.removeValue(forKey: identity)
            activation.activity.suspend()
        }

        for (identity, activity) in desired where activations[identity] == nil {
            // `activate` may synchronously end an entire source. The loop walks
            // a value snapshot, so re-check the live desired map before every
            // later entry instead of reviving an object removed by an earlier
            // activation callback.
            guard desiredVisibleActivities[identity] === activity,
                  isRegistered(activity) || retainedOutgoingActivities[identity] != nil else {
                continue
            }
            let logicalID = activity.id
            let context = LiveActivityContext { [weak self, weak activity] in
                guard let activity else { return }
                self?.invalidate(
                    identity : identity,
                    logicalID: logicalID,
                    activity : activity
                )
            }
            activations[identity] = Activation(activity: activity, context: context)
            activity.activate(in: context)
        }
    }

    /// retainOutgoingIfPresented keeps an exact replaced object eligible only
    /// while a submitted root still owns it. The next complete projection that
    /// omits it releases this strong reference and permanently rejects replay.
    private func retainOutgoingIfPresented(_ activity: any NotchActivity) {
        let identity = ObjectIdentifier(activity)
        guard desiredVisibleActivities[identity] != nil || activations[identity] != nil else { return }
        retainedOutgoingActivities[identity] = activity
    }

    private func isRegistered(_ activity: any NotchActivity) -> Bool {
        persistent.contains { $0.activity === activity }
            || notices.contains { $0.activity === activity }
            || expandedFallback.map { $0 === activity } == true
    }

    /// revokeRetainedActivities terminates every matching desired or active
    /// instance, including same-ID objects displaced from the logical registry.
    /// The optional preserved identity keeps an explicitly selected fallback
    /// valid when its finite live-session role ends.
    @discardableResult
    private func revokeRetainedActivities(
        where predicate       : (any NotchActivity) -> Bool,
        preserving identityToPreserve: ObjectIdentifier? = nil
    ) -> Bool {
        var revoked: Set<ObjectIdentifier> = []
        for (identity, activity) in desiredVisibleActivities
            where identity != identityToPreserve && predicate(activity) {
            revoked.insert(identity)
        }
        for (identity, activation) in activations
            where identity != identityToPreserve && predicate(activation.activity) {
            revoked.insert(identity)
        }
        for (identity, activity) in retainedOutgoingActivities
            where identity != identityToPreserve && predicate(activity) {
            revoked.insert(identity)
        }
        guard !revoked.isEmpty else { return false }
        for identity in revoked {
            desiredVisibleActivities.removeValue(forKey: identity)
            retainedOutgoingActivities.removeValue(forKey: identity)
        }
        reconcileActivations()
        presentationValidityRevision &+= 1
        onValidityChange?()
        return true
    }

    /// invalidate accepts updates only from the exact activated registry object.
    /// A late context from a same-ID replacement cannot mutate the new entry.
    private func invalidate(
        identity : ObjectIdentifier,
        logicalID: String,
        activity : any NotchActivity
    ) {
        guard activations[identity]?.activity === activity else { return }
        if let index = persistent.firstIndex(where: {
            $0.activity.id == logicalID && $0.activity === activity
        }) {
            let live = persistent[index].activity
            let revision = live.contentRevision
            let lifetime = live.lifetime
            let relevance = normalizedRelevance(live.relevanceScore)
            guard persistent[index].revision != revision
                    || persistent[index].lifetime != lifetime
                    || persistent[index].relevance != relevance else { return }
            persistent[index].revision = revision
            persistent[index].lifetime = lifetime
            persistent[index].relevance = relevance
        } else if let index = notices.firstIndex(where: {
            $0.activity.id == logicalID && $0.activity === activity
        }) {
            let revision = notices[index].activity.contentRevision
            guard notices[index].revision != revision else { return }
            notices[index].revision = revision
        } else if expandedFallback !== activity {
            return
        }
        expireNotices()
    }

    private func key(for activity: (any NotchActivity)?) -> ContentKey? {
        activity.map {
            ContentKey(
                identity: ObjectIdentifier($0),
                revision: $0.contentRevision,
                isStale : isStale($0)
            )
        }
    }

    private func normalizedRelevance(_ score: Double) -> Double {
        score.isFinite ? min(1, max(0, score)) : 0
    }

    private var rankedLiveEntries: [LiveEntry] {
        persistent.sorted {
            $0.relevance == $1.relevance ? $0.order > $1.order : $0.relevance > $1.relevance
        }
    }

    private func scheduleExpiration() {
        let instant = now()
        var next = notices.map(\.expires).min()
        for entry in persistent {
            let end = entry.expiresAt
            next = next.map { min($0, end) } ?? end
            if let stale = entry.lifetime.staleDate, stale > instant {
                next = next.map { min($0, stale) } ?? stale
            }
        }
        guard next != scheduledDeadline else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadline = next
        guard let next else { return }
        let delay = max(0, next.timeIntervalSince(instant))
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scheduledDeadline = nil
            self.deadlineTask = nil
            self.expireNotices()
        }
    }

    deinit { deadlineTask?.cancel() }
}
