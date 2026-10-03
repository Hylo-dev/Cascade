//
//  RuntimeOptionsState.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeOptionsState owns one options lease. Preparation retains nothing; the
/// runtime must reserve the quoted bytes and revalidate before committing it.
struct RuntimeOptionsState: Sendable {

    private struct LeaseBinding: Sendable {

        let owner     : AddonID
        let generation: ConnectionGeneration
    }

    static let maximumBindings = 256
    static let bindingBytes    = 128

    private(set) var active: AddonOptionsPresentation?
    private var bindings   : [UUID: LeaseBinding] = [:]

    var retainedBytes: Int {
        bindings.count * Self.bindingBytes + (active.map { Self.bytes($0.request) } ?? 0)
    }

    func retainedBytes(owner: AddonID) -> Int {
        let history = bindings.values.filter { $0.owner == owner }.count * Self.bindingBytes
        return history
            + (active.flatMap {
                $0.request.publicationID.addonID == owner ? Self.bytes($0.request) : nil
            } ?? 0)
    }

    func preparationBytes(_ presentation: AddonOptionsPresentation) -> Int {
        Self.bytes(presentation.request)
            + (bindings[presentation.request.leaseID] == nil ? Self.bindingBytes : 0)
    }

    static func bytes(_ request: AddonOptionsRequest) -> Int {
        // The value document, asset-reference array and original action binding are
        // paid together. ContentDocument already caps encoded content at 64 KiB.
        (try? JSONEncoder().encode(request).count).map { $0 * 4 + 4_096 } ?? 282_624
    }

    /// validateAggregateBudget also runs for source-only updates, since the old
    /// detail remains mounted while its controls await the new source revision.
    static func validateAggregateBudget(
        source    : Publication,
        document  : ContentDocument,
        at instant: Date
    ) throws {
        let detailBytes   = try JSONEncoder().encode(document).count
        let presentations = source.content.map { [$0] } ?? source.timeline?.map(\.content) ?? []
        for presentation in presentations {
            guard try JSONEncoder().encode(presentation).count + detailBytes <= 65_536 else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "Options exceeds the aggregate presentation budget."
                )
            }
        }
    }

    /// prepare binds only an actual accepted delivery, or the identical active lease.
    /// A refresh may adopt a newer source revision but never renew the original expiry.
    func prepare(
        _ request      : AddonOptionsRequest,
        context        : ActionAuthorizer.Context,
        action         : ActionRequest?,
        origin         : AddonOptionsOrigin?,
        generation     : ConnectionGeneration,
        supportsOptions: Bool,
        at instant     : Date
    ) throws -> AddonOptionsPresentation {
        try request.validate()
        guard supportsOptions,
            let publication      = context.publication,
            publication.kind     == .widget,
            publication.id       == request.publicationID,
            publication.revision == request.observedRevision,
            publication.expiresAt > instant,
            context.eligibility == .available,
            context.installed.enabled,
            context.resolution.acceptedAddons.contains(publication.id.addonID),
            !context.resolution.blockedAddons.contains(where: {
                $0.addonID == publication.id.addonID
            }),
            context.resolution.enabledFeatures.contains(where: {
                $0.addonID == publication.id.addonID && $0.featureID == context.featureID
            }),
            !context.resolution.blockedFeatures.contains(where: {
                $0.addonID == publication.id.addonID && $0.featureID == context.featureID
            }),
            context.installed.manifest.features.first(where: { $0.id == context.featureID })?
                .supportsFullscreen == true
        else {
            throw AddonFailure(code: .permissionDenied, reason: "Options source is unavailable.")
        }

        let selectedOrigin: AddonOptionsOrigin
        let deadline      : Date
        if let active, active.request.leaseID == request.leaseID {
            guard active.generation == generation,
                active.request.publicationID   == request.publicationID,
                active.request.actionRequestID == request.actionRequestID,
                active.origin.isValid,
                active.expiresAt > instant
            else { throw AddonFailure(code: .sessionRevoked, reason: "Options lease was revoked.") }
            selectedOrigin = active.origin
            deadline       = min(active.expiresAt, publication.expiresAt)
        } else {
            guard bindings[request.leaseID] == nil, bindings.count < Self.maximumBindings else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "Options lease ID is retired or its bounded history is full."
                )
            }
            guard active?.request.actionRequestID != request.actionRequestID,
                active.map({ $0.origin !== origin }) ?? true
            else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Options opening action was already used."
                )
            }
            guard let action, let origin,
                action.requestID        == request.actionRequestID,
                action.publicationID    == request.publicationID,
                action.observedRevision == request.observedRevision,
                origin.publicationID    == request.publicationID,
                origin.observedRevision == request.observedRevision,
                origin.isValid
            else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Options requires its accepted user action."
                )
            }
            try ActionAuthorizer.validate(action, context: context, at: instant)
            selectedOrigin = origin
            deadline       = publication.expiresAt
        }

        let declarations =
            context.installed.manifest.features.first { $0.id == context.featureID }?.actions ?? []
        guard Set(request.document.root.actionIdentifiers).isSubset(of: Set(declarations)) else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Options contains undeclared actions."
            )
        }
        // Options share the source publication's asset capability, including its
        // separately published expanded document. A request cannot widen that scope.
        let presentation =
            publication.content ?? publication.timeline?.last { $0.date <= instant }?.content
        guard presentation?.widget?.privacy == .publicContent else {
            throw AddonFailure(code: .permissionDenied, reason: "Options source is redacted.")
        }
        // A source and its detail coexist. They share PresentationSet's existing
        // aggregate bound, even though each document is individually bounded.
        try Self.validateAggregateBudget(
            source  : publication,
            document: request.document,
            at      : instant
        )
        let sourceAssets = [
            presentation?.widget,
            presentation?.compactLeading,
            presentation?.compactTrailing,
            presentation?.minimal,
            presentation?.expanded,
        ].compactMap { $0 }.flatMap(\.assets)
        guard Set(request.document.assets).isSubset(of: Set(sourceAssets)) else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "Options contains unbound asset references."
            )
        }
        return AddonOptionsPresentation(
            request   : request,
            origin    : selectedOrigin,
            generation: generation,
            expiresAt : deadline
        )
    }

    mutating func commit(_ presentation: AddonOptionsPresentation) {
        if let active, active.request.leaseID != presentation.request.leaseID {
            active.origin.revoke()
        }
        bindings[presentation.request.leaseID] = LeaseBinding(
            owner     : presentation.request.publicationID.addonID,
            generation: presentation.generation
        )
        active = presentation
    }

    /// dismiss revokes only the exact lease, making stale dismiss operations harmless.
    @discardableResult
    mutating func dismiss(_ leaseID: UUID) -> Bool {
        guard active?.request.leaseID == leaseID else { return false }
        active?.origin.revoke()
        active = nil
        return true
    }

    /// invalidateGeneration clears paid tombstones only when their canonical
    /// connection loses authority; Back and source withdrawal keep the replay guard.
    mutating func invalidateGeneration(owner: AddonID, generation: ConnectionGeneration) {
        bindings = bindings.filter { $0.value.owner != owner || $0.value.generation != generation }
    }

    func controlsAvailable(
        context   : ActionAuthorizer.Context,
        generation: ConnectionGeneration,
        at instant: Date
    ) -> Bool {
        guard let active,
            active.origin.isValid,
            active.generation == generation,
            active.expiresAt > instant,
            active.request.document.privacy == .publicContent,
            context.eligibility == .available,
            context.publication?.id == active.request.publicationID,
            context.publication?.revision == active.request.observedRevision,
            (context.publication?.expiresAt ?? .distantPast) > instant,
            (context.publication?.content
                ?? context.publication?.timeline?.last { $0.date <= instant }?.content)?.widget?
                .privacy == .publicContent
        else { return false }
        return true
    }

    /// actionContext keeps the existing journal, deadlines and payload checks while
    /// authorizing the current leased representation instead of compact content.
    func actionContext(
        context   : ActionAuthorizer.Context,
        leaseID   : UUID,
        generation: ConnectionGeneration,
        at instant: Date
    ) throws -> ActionAuthorizer.Context {
        guard let active, active.request.leaseID == leaseID,
            controlsAvailable(context: context, generation: generation, at: instant)
        else {
            throw AddonFailure(code: .sessionRevoked, reason: "Options controls are unavailable.")
        }
        return ActionAuthorizer.Context(
            installed         : context.installed,
            resolution        : context.resolution,
            featureID         : context.featureID,
            publication       : context.publication,
            eligibility       : context.eligibility,
            authorizedDocument: active.request.document
        )
    }
}
