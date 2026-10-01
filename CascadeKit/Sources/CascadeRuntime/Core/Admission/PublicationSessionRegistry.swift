//
//  PublicationSessionRegistry.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PublicationConnection is an opaque host-issued handle. Its readable generation
/// and negotiation are descriptive; only the issuing state owner's canonical record
/// grants authority. It cannot be initialized or decoded by transport clients.
public struct PublicationConnection: Equatable, Sendable {

    fileprivate let token: UUID
    fileprivate let owner: AddonID

    public let generation        : ConnectionGeneration
    public let negotiatedProtocol: NegotiatedProtocol

    fileprivate init(
        owner             : AddonID,
        negotiatedProtocol: NegotiatedProtocol
    ) {
        token                   = UUID()
        self.owner              = owner
        generation              = ConnectionGeneration()
        self.negotiatedProtocol = negotiatedProtocol
    }
}

/// PublicationSessionRegistry keeps only host-issued authority and retained
/// publisher bindings. PublicationState's owner serializes all access without
/// suspension; the registry returns its exact accounting deltas so it cannot release
/// bytes owned by publication records or another runtime component.
struct PublicationSessionRegistry: Sendable {

    struct Accounting: Equatable, Sendable {

        let connectionBytes: Int
        let namespaceBytes : Int
    }

    /// NamespaceBinding is a nonmutating quote for a verified publisher binding.
    /// It creates no connection, provider generation or sequence authority.
    struct NamespaceBinding: Sendable {

        fileprivate let identity: VerifiedAddonIdentity

        let additionalBytes: Int

        fileprivate init(
            identity       : VerifiedAddonIdentity,
            additionalBytes: Int
        ) {
            self.identity        = identity
            self.additionalBytes = additionalBytes
        }
    }

    struct Session: Sendable {

        let connection            : PublicationConnection
        let identity              : VerifiedAddonIdentity
        let verifiedDigest        : String
        let authorizedPublications: Set<PublicationID>
        var lastSequence          : UInt64
    }

    private static let connectionCharge = 4_096
    private static let namespaceCharge  = 1_024

    private let maximumConnections        : Int
    private let maximumPublisherNamespaces: Int

    private var connections: [AddonID: Session] = [:]
    private var publishers : [AddonID: String]  = [:]

    init(
        maximumConnections        : Int,
        maximumPublisherNamespaces: Int
    ) {
        self.maximumConnections         = min(32, max(0, maximumConnections))
        self.maximumPublisherNamespaces = min(256, max(0, maximumPublisherNamespaces))
    }

    /// namespaceAdmissionBytes validates publisher ownership before quoting namespace-only growth.
    func namespaceAdmissionBytes(identity: VerifiedAddonIdentity) throws -> Int {
        guard !identity.publisher.isEmpty, identity.publisher.utf8.count <= 512 else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Verified publisher must contain 1...512 UTF-8 bytes."
            )
        }

        if let publisher = publishers[identity.addonID] {
            guard publisher == identity.publisher else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "This addon namespace belongs to another verified publisher."
                )
            }
            return 0
        }

        guard publishers.count < maximumPublisherNamespaces else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The publisher namespace capacity is exhausted."
            )
        }

        return Self.namespaceCharge
    }

    /// prepareNamespace checks the available state budget without retaining publisher authority.
    func prepareNamespace(
        identity      : VerifiedAddonIdentity,
        availableBytes: Int
    ) throws -> NamespaceBinding {
        let bytes = try namespaceAdmissionBytes(identity: identity)
        guard bytes <= availableBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The retained publication state budget is exhausted."
            )
        }

        return NamespaceBinding(identity: identity, additionalBytes: bytes)
    }

    /// bindNamespace commits a quote only within the caller's already validated state transition.
    /// PublicationState guards its issuer/revision and serializes this with record installation.
    mutating func bindNamespace(_ binding: NamespaceBinding) {
        precondition(
            publishers[binding.identity.addonID] == nil
                || publishers[binding.identity.addonID] == binding.identity.publisher
        )
        publishers[binding.identity.addonID] = binding.identity.publisher
    }

    /// additionalBytes projects the exact connection and namespace growth without
    /// minting authority, so the runtime can reserve its owner pool first.
    func additionalBytes(identity: VerifiedAddonIdentity) throws -> Int {
        let namespaceBytes  = try namespaceAdmissionBytes(identity: identity)
        let isNewConnection = connections[identity.addonID] == nil
        guard !isNewConnection || connections.count < maximumConnections else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The publication connection capacity is exhausted."
            )
        }

        return (isNewConnection ? Self.connectionCharge : 0) + namespaceBytes
    }

    /// open validates all inputs and capacity before changing either dictionary.
    /// Replacements keep the old authority until negotiation and reservation succeed.
    mutating func open(
        identity                    : VerifiedAddonIdentity,
        verifiedDigest              : String,
        manifestProtocol            : ProtocolVersion,
        offer                       : ProtocolOffer,
        authorizedPublications      : [PublicationID],
        contentSchemas              : [Int],
        availableBytes              : Int,
        supportsKeyedStorageFrames  : Bool = false,
        supportsAssetFrames         : Bool = false,
        supportsFileWorkspaceContent: Bool = false,
        serviceHost                 : Bool = false,
        subscriptionHost            : Bool = false
    ) throws -> (
        connection     : PublicationConnection,
        additionalBytes: Int
    ) {
        guard !identity.publisher.isEmpty,
              identity.publisher.utf8.count <= 512,
              !verifiedDigest.isEmpty,
              verifiedDigest.utf8.count <= 512
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Verified publisher and digest must contain 1...512 UTF-8 bytes."
            )
        }
        guard authorizedPublications.count <= 16,
              Set(authorizedPublications).count == authorizedPublications.count,
              authorizedPublications.allSatisfy({ $0.addonID == identity.addonID })
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Host assignment requires at most 16 distinct publications owned by the addon."
            )
        }

        _              = try additionalBytes(identity: identity)
        let negotiated = try ProtocolNegotiator.negotiate(
            offer                       : offer,
            manifestProtocol            : manifestProtocol,
            contentSchemas              : contentSchemas,
            supportsKeyedStorageFrames  : supportsKeyedStorageFrames,
            supportsAssetFrames         : supportsAssetFrames,
            supportsFileWorkspaceContent: supportsFileWorkspaceContent,
            serviceHost                 : serviceHost,
            subscriptionHost            : subscriptionHost
        )

        let isNewConnection = connections[identity.addonID] == nil
        let isNewNamespace  = publishers[identity.addonID] == nil
        guard !isNewConnection || connections.count < maximumConnections,
              !isNewNamespace || publishers.count < maximumPublisherNamespaces
        else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The publication connection or namespace capacity is exhausted."
            )
        }

        let additionalBytes = try additionalBytes(identity: identity)
        guard additionalBytes <= availableBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The retained publication state budget is exhausted."
            )
        }

        let connection                = PublicationConnection(
            owner             : identity.addonID,
            negotiatedProtocol: negotiated
        )
        publishers[identity.addonID]  = identity.publisher
        connections[identity.addonID] = Session(
            connection            : connection,
            identity              : identity,
            verifiedDigest        : verifiedDigest,
            authorizedPublications: Set(authorizedPublications),
            lastSequence          : 0
        )
        return (connection, additionalBytes)
    }

    /// validate resolves authority from the canonical record before checking replay.
    func validate(
        connection: PublicationConnection,
        generation: ConnectionGeneration,
        sequence  : UInt64
    ) throws -> Session {
        guard let session = connections[connection.owner],
              session.connection == connection,
              session.connection.generation == generation
        else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The publication connection is no longer authorized."
            )
        }
        guard sequence > 0, sequence > session.lastSequence else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Output sequence is zero, stale or reused."
            )
        }

        return session
    }

    /// advance records a successful commit. Its caller holds the same actor turn
    /// since validate, so revocation cannot interleave or be silently reversed.
    mutating func advance(
        _ session: Session,
        sequence : UInt64
    ) {
        var updated                           = session
        updated.lastSequence                  = sequence
        connections[session.identity.addonID] = updated
    }

    /// close releases only the matching active handle, keeping publisher identity
    /// and all publication history. Closing a superseded handle is a no-op.
    mutating func close(_ connection: PublicationConnection) -> Int {
        guard connections[connection.owner]?.connection == connection else { return 0 }

        connections.removeValue(forKey: connection.owner)
        return Self.connectionCharge
    }

    /// remove revokes active authority before releasing the retained namespace.
    mutating func remove(owner: AddonID) -> Int {
        let connectionBytes = connections.removeValue(forKey: owner) == nil ? 0 : Self.connectionCharge
        let namespaceBytes  = publishers.removeValue(forKey: owner) == nil ? 0 : Self.namespaceCharge
        return connectionBytes + namespaceBytes
    }

    /// accounting exposes canonical component charges without leaking session records.
    func accounting(owner: AddonID) -> Accounting {
        Accounting(
            connectionBytes: connections[owner] == nil ? 0 : Self.connectionCharge,
            namespaceBytes : publishers[owner] == nil ? 0 : Self.namespaceCharge
        )
    }
}
