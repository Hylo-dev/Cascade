//
//  ActionAuthorizer.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// ActionAuthorizer checks canonical host snapshots, never authenticates a process.
public enum ActionAuthorizer {
    public enum Failure: Error, Equatable, Sendable {
        case unavailable, identityMismatch, featureUnavailable, undeclaredAction
        case expired, staleRevision, unpublishedAction, payloadMismatch, ambiguousPayload
    }

    public enum Eligibility: Sendable {
        case available, unavailable, stale, privacyRedacted, hidden
    }

    /// Context contains transient host-owned state. The feature binding must come
    /// from publication admission, never from provider action names or UI input.
    public struct Context: Sendable {
        public let installed: InstalledAddon
        public let resolution: Resolution
        public let featureID: String
        public let publication: Publication?
        public let eligibility: Eligibility

        public init(
            installed  : InstalledAddon,
            resolution : Resolution,
            featureID  : String,
            publication: Publication?,
            eligibility: Eligibility = .unavailable
        ) {
            self.installed = installed
            self.resolution = resolution
            self.featureID = featureID
            self.publication = publication
            self.eligibility = eligibility
        }
    }

    struct Binding: Equatable, Sendable {
        let identity: VerifiedAddonIdentity
        let digest: String
        let featureID: String
    }

    public static func validate(
        _ request: ActionRequest,
        context  : Context,
        at wall  : Date
    ) throws {
        try validate(
            request,
            context             : context,
            at                  : wall,
            checkRequestDeadline: true
        )
    }

    /// binding validates access to retained history independently of publication lifetime.
    /// The host still supplies current identity, feature and explicit recovery eligibility.
    static func binding(
        _ request: ActionRequest,
        context  : Context
    ) throws -> Binding {
        let installed = context.installed
        let owner = installed.manifest.id
        guard installed.verifiedIdentity.addonID == owner,
            request.publicationID.addonID == owner,
            installed.verifiedIdentity.publisher.utf8.count <= 4_096
        else { throw Failure.identityMismatch }
        guard installed.enabled, context.eligibility == .available,
            context.resolution.acceptedAddons.contains(owner),
            !context.resolution.blockedAddons.contains(where: { $0.addonID == owner })
        else { throw Failure.unavailable }
        guard let feature = installed.manifest.features.first(where: { $0.id == context.featureID }),
            context.resolution.enabledFeatures.contains(where: { $0.addonID == owner && $0.featureID == feature.id }),
            !context.resolution.blockedFeatures.contains(where: { $0.addonID == owner && $0.featureID == feature.id })
        else { throw Failure.featureUnavailable }
        guard feature.actions?.contains(request.actionID) == true else { throw Failure.undeclaredAction }
        return Binding(
            identity : installed.verifiedIdentity,
            digest   : installed.digest,
            featureID: feature.id
        )
    }

    /// validate performs one action scan over the already validated immutable contracts.
    /// Final delivery uses the journal's anchored monotonic deadline instead of
    /// reinterpreting the request's civil deadline after a clock adjustment.
    static func validate(
        _ request: ActionRequest,
        context             : Context,
        at wall             : Date,
        checkRequestDeadline: Bool
    ) throws {
        try request.validate()
        guard let publication = context.publication, publication.id == request.publicationID else {
            throw Failure.identityMismatch
        }
        _ = try binding(
            request,
            context: context
        )
        guard wall.timeIntervalSince1970.isFinite,
            publication.expiresAt > wall,
            !checkRequestDeadline || request.deadline > wall
        else { throw Failure.expired }
        guard publication.revision == request.observedRevision else { throw Failure.staleRevision }
        let presentation = publication.content ?? publication.timeline?.last(where: { $0.date <= wall })?.content
        guard let presentation else { throw Failure.unpublishedAction }
        var payload: Data?
        func visit(_ node: ContentNode) throws {
            if node.kind == .action, node.actionID == request.actionID {
                let candidate = node.actionPayload ?? Data()
                if let payload, payload != candidate { throw Failure.ambiguousPayload }
                payload = candidate
            }
            for child in node.children ?? [] { try visit(child) }
        }
        for document in [presentation.widget, presentation.compactLeading,
                         presentation.compactTrailing, presentation.minimal, presentation.expanded] {
            if let document { try visit(document.root) }
        }
        guard let payload else { throw Failure.unpublishedAction }
        guard payload == request.input else { throw Failure.payloadMismatch }
    }
}
