//
//  PublicationStore.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PublicationStore preserves the actor-based publication API for existing clients.
/// Its only mutable authority is one synchronous PublicationState value, so a runtime
/// can own the same state machine directly without introducing a second registry.
public actor PublicationStore {
    public static let maximumStateBytes = PublicationState.maximumStateBytes

    private var state: PublicationState

    public var retainedBytes: Int {
        state.retainedBytes
    }

    public init(
        maximumRetainedBytes      : Int = maximumStateBytes,
        maximumConnections        : Int = 32,
        maximumPublisherNamespaces: Int = 256,
        now                       : @escaping @Sendable () -> Date = Date.init
    ) {
        state = PublicationState(
            maximumRetainedBytes      : maximumRetainedBytes,
            maximumConnections        : maximumConnections,
            maximumPublisherNamespaces: maximumPublisherNamespaces,
            now                       : now
        )
    }

    /// openConnection delegates host-verified connection admission to the canonical
    /// synchronous state owned by this actor.
    public func openConnection(
        identity                    : VerifiedAddonIdentity,
        verifiedDigest              : String,
        manifestProtocol            : ProtocolVersion,
        offer                       : ProtocolOffer,
        authorizedPublications      : [PublicationID],
        contentSchemas              : [Int] = [1, 2],
        supportsFileWorkspaceContent: Bool = false
    ) throws -> PublicationConnection {
        try state.openConnection(
            identity                    : identity,
            verifiedDigest              : verifiedDigest,
            manifestProtocol            : manifestProtocol,
            offer                       : offer,
            authorizedPublications      : authorizedPublications,
            contentSchemas              : contentSchemas,
            supportsFileWorkspaceContent: supportsFileWorkspaceContent
        )
    }

    /// closeConnection revokes only this handle while retaining publications and the
    /// publisher binding. An obsolete or foreign-store handle remains a no-op.
    public func closeConnection(_ connection: PublicationConnection) {
        state.closeConnection(connection)
    }

    /// acceptPublicationState delegates complete output validation and its atomic
    /// publication/session commit to the canonical synchronous state.
    public func acceptPublicationState(
        _ output          : ProviderOutput,
        connection        : PublicationConnection,
        generation        : ConnectionGeneration,
        sequence          : UInt64,
        expectedCompletion: CompletionExpectation? = nil
    ) throws -> PublicationAdmission {
        try state.acceptPublicationState(
            output,
            connection        : connection,
            generation        : generation,
            sequence          : sequence,
            expectedCompletion: expectedCompletion
        )
    }

    /// accept is a trusted host composition primitive, not transport ingress.
    /// Admission is transactional: failure leaves the last valid publication untouched.
    public func accept(_ publication: Publication, owner: AddonID) throws {
        try state.accept(publication, owner: owner)
    }

    /// accept commits a trusted host batch as one actor operation. Transport callers
    /// must enter through acceptPublicationState instead.
    public func accept(_ publications: [Publication], owner: AddonID) throws {
        try state.accept(publications, owner: owner)
    }

    /// snapshot selects due entries and preserves pending timelines without a provider
    /// tick. Missing identities mean revoked or expired, never merely waiting.
    public func snapshot(at date: Date) -> [Publication] {
        state.snapshot(at: date)
    }

    /// nextDeadline returns the next publication expiry or timeline transition.
    public func nextDeadline(after date: Date) -> Date? {
        state.nextDeadline(after: date)
    }

    /// remove ends this session without permitting its revision to be replayed.
    public func remove(id: PublicationID, owner: AddonID) throws {
        try state.remove(id: id, owner: owner)
    }

    /// remove revokes connection authority and clears all state for one owner.
    public func remove(owner: AddonID) {
        state.remove(owner: owner)
    }

    /// expire terminally removes content whose deadline has passed.
    public func expire(at date: Date) {
        state.expire(at: date)
    }
}
