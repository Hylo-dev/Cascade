//
//  PublicationState.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PublicationState owns the complete synchronous publication and connection state
/// machine. A serializing actor holds one value directly; copying it creates an
/// independent authority rather than a shared or mirrored registry.
struct PublicationState: Sendable {
    struct RecordAccounting: Equatable, Sendable {
        let owner: AddonID
        let revision: UInt64
        let kind: Publication.Kind
        let contentBytes: Int
        let tombstoneBytes: Int
    }

    struct PreparedOutput: Sendable {
        fileprivate let records: [PublicationID: Record]
        fileprivate let previousLiveDeadlines: [PublicationID: Date]
        fileprivate let session: PublicationSessionRegistry.Session
        fileprivate let sequence: UInt64
        fileprivate let stateRevision: UInt64
        let owner: AddonID
        let retainedBytesAfter: Int
        let newFamilies: [PublicationID: Publication.Kind]
        let admission: PublicationAdmission

        /// forEachChangedPublication visits admitted, host-capped publications in this proposal.
        /// Preparation is not committed authority: consumers must complete the state's
        /// validated commit before applying external effects or retaining references.
        func forEachChangedPublication(_ visit: (Publication) throws -> Void) rethrows {
            for record in records.values {
                if let publication = record.publication { try visit(publication) }
            }
        }

        /// forEachEndedPublicationID visits canonical ended records, excluding no-op requests
        /// for identities without retained content. Subject to the same commit guard.
        func forEachEndedPublicationID(_ visit: (PublicationID) throws -> Void) rethrows {
            for (id, record) in records where record.publication == nil { try visit(id) }
        }
    }

    struct PreparedCompletion: Sendable {
        fileprivate let session: PublicationSessionRegistry.Session
        fileprivate let sequence: UInt64
        let admission: PublicationAdmission
    }
    fileprivate struct Record: Sendable {
        let revision       : UInt64
        let kind           : Publication.Kind
        let sessionDeadline: Date
        var publication    : Publication?
        var contentBytes   : Int
    }

    private struct ActiveCounts: Sendable {
        var owner           = 0
        var activities      = 0
        var ownerActivities = 0
        var notices         = 0
    }

    static let maximumStateBytes = 8 * 1_024 * 1_024

    // Conservative accounting for dictionary entries, identities and replay tombstones.
    private static let recordCharge = 1_024

    private var restorationIssuer = UUID()
    private let maximumRetainedBytes: Int
    private let now                 : @Sendable () -> Date
    private var records             : [PublicationID: Record] = [:]
    private var sessions            : PublicationSessionRegistry
    private(set) var retainedBytes  = 0
    private var stateRevision: UInt64 = 0
    private var isRevisionExhausted = false

    init(
        maximumRetainedBytes      : Int = maximumStateBytes,
        maximumConnections        : Int = 32,
        maximumPublisherNamespaces: Int = 256,
        now                       : @escaping @Sendable () -> Date = Date.init
    ) {
        self.maximumRetainedBytes = min(
            Self.maximumStateBytes,
            max(
                0,
                maximumRetainedBytes
            )
        )
        self.now                  = now
        sessions = PublicationSessionRegistry(
            maximumConnections        : maximumConnections,
            maximumPublisherNamespaces: maximumPublisherNamespaces
        )
    }

    /// openConnection admits only host-verified identity, digest and assignments.
    /// Failure preserves previous authority; successful replacement keeps publication
    /// history while issuing a fresh generation and sequence state.
    mutating func openConnection(
        identity                  : VerifiedAddonIdentity,
        verifiedDigest            : String,
        manifestProtocol          : ProtocolVersion,
        offer                     : ProtocolOffer,
        authorizedPublications    : [PublicationID],
        contentSchemas            : [Int] = [1, 2],
        supportsKeyedStorageFrames: Bool = false,
        supportsAssetFrames       : Bool = false,
        serviceHost               : Bool = false,
        subscriptionHost          : Bool = false
    ) throws -> PublicationConnection {
        let admission = try sessions.open(
            identity                  : identity,
            verifiedDigest            : verifiedDigest,
            manifestProtocol          : manifestProtocol,
            offer                     : offer,
            authorizedPublications    : authorizedPublications,
            contentSchemas            : contentSchemas,
            availableBytes            : maximumRetainedBytes - retainedBytes,
            supportsKeyedStorageFrames: supportsKeyedStorageFrames,
            supportsAssetFrames       : supportsAssetFrames,
            serviceHost               : serviceHost,
            subscriptionHost          : subscriptionHost
        )
        retainedBytes += admission.additionalBytes
        advanceStateRevision()
        return admission.connection
    }

    /// connectionAdmissionBytes exposes the exact nonmutating session growth so its
    /// actor owner can prepay the canonical pool before retaining a new handle.
    func connectionAdmissionBytes(identity: VerifiedAddonIdentity) throws -> Int {
        try sessions.additionalBytes(identity: identity)
    }

    /// closeConnection revokes only this handle, retaining publications and publisher
    /// binding. An obsolete or foreign-state handle cannot close current authority.
    mutating func closeConnection(_ connection: PublicationConnection) {
        let released = sessions.close(connection)
        retainedBytes -= released
        if released > 0 { advanceStateRevision() }
    }

    /// acceptPublicationState validates the complete output before committing its
    /// publications. Returned operations (including endPublication), completion and
    /// checkpoint remain values for the coordinator: no external effect is authorized,
    /// executed, persisted or journaled here. No suspension separates canonical session
    /// validation, bounded batch rollback and sequence advancement.
    mutating func acceptPublicationState(
        _ output          : ProviderOutput,
        connection        : PublicationConnection,
        generation        : ConnectionGeneration,
        sequence          : UInt64,
        expectedCompletion: CompletionExpectation? = nil
    ) throws -> PublicationAdmission {
        let session = try sessions.validate(
            connection: connection,
            generation: generation,
            sequence  : sequence
        )
        try output.validate()
        for publication in output.publications {
            guard session.authorizedPublications.contains(publication.id) else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Publication identity was not assigned by the host."
                )
            }
        }
        for operation in output.operations {
            if case .endPublication(let id) = operation,
               !session.authorizedPublications.contains(id) {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Publication identity was not assigned by the host."
                )
            }
        }
        var previousRevisions: [PublicationID: UInt64] = [:]
        for publication in output.publications {
            previousRevisions[publication.id] = records[publication.id]?.revision
        }
        try output.validateContext(
            authenticatedAddonID: session.identity.addonID,
            expectedCompletion  : expectedCompletion,
            previousRevisions   : previousRevisions,
            contentSchemas      : session.connection.negotiatedProtocol.contentSchemas
        )
        try accept(
            output.publications,
            owner: session.identity.addonID
        )
        sessions.advance(
            session,
            sequence: sequence
        )
        advanceStateRevision()
        return PublicationAdmission(
            operations: output.operations,
            completion: output.completion,
            checkpoint: output.checkpoint
        )
    }

    /// prepareOutput validates and projects only the touched bounded batch without mutation.
    /// Its revision token is state authority, while the provider sequence remains session replay state.
    func prepareOutput(
        _ output          : ProviderOutput,
        connection        : PublicationConnection,
        generation        : ConnectionGeneration,
        sequence          : UInt64,
        expectedCompletion: CompletionExpectation? = nil
    ) throws -> PreparedOutput {
        guard !isRevisionExhausted else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Publication authority revision is exhausted."
            )
        }
        let session = try sessions.validate(
            connection: connection,
            generation: generation,
            sequence  : sequence
        )
        try output.validate()
        guard output.operations.allSatisfy({
            if case .endPublication = $0 { return true }
            return false
        }) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "This runtime cut does not support the requested output operation."
            )
        }
        for publication in output.publications {
            guard session.authorizedPublications.contains(publication.id) else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Publication identity was not assigned by the host."
                )
            }
        }
        for operation in output.operations {
            if case .endPublication(let id) = operation,
               !session.authorizedPublications.contains(id) {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "Publication identity was not assigned by the host."
                )
            }
        }
        var previousRevisions: [PublicationID: UInt64] = [:]
        for publication in output.publications {
            previousRevisions[publication.id] = records[publication.id]?.revision
        }
        try output.validateContext(
            authenticatedAddonID: session.identity.addonID,
            expectedCompletion  : expectedCompletion,
            previousRevisions   : previousRevisions,
            contentSchemas      : session.connection.negotiatedProtocol.contentSchemas
        )
        let instant = now()
        var counts = activeCounts(
            owner: session.identity.addonID,
            at   : instant
        )
        var proposed: [PublicationID: Record] = [:]
        var projectedBytes = retainedBytes
        for publication in output.publications {
            try publication.validateOwnerAndStructure(session.identity.addonID)
            guard instant.timeIntervalSince1970.isFinite, publication.expiresAt > instant else {
                throw AddonFailure(
                    code  : .deadlineExceeded,
                    reason: "Publication has expired."
                )
            }
            let previous = proposed[publication.id] ?? records[publication.id]
            try publication.validateRevision(after: previous?.revision)
            if let previous {
                guard let retained = previous.publication, retained.expiresAt > instant else {
                    throw AddonFailure(
                        code  : .sessionRevoked,
                        reason: "An ended publication requires a new host-negotiated session."
                    )
                }
            }
            guard previous == nil || previous?.kind == publication.kind else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "A publication session cannot change its family."
                )
            }
            let duration: TimeInterval = publication.kind == .activity
                ? 8 * 3_600
                : (publication.kind == .notice ? 10 : .infinity)
            let sessionDeadline = previous?.sessionDeadline
                ?? (duration.isFinite ? instant.addingTimeInterval(duration) : .distantFuture)
            guard sessionDeadline > instant else {
                throw AddonFailure(
                    code  : .sessionRevoked,
                    reason: "The publication session has ended."
                )
            }
            let admitted = try publication.capped(at: sessionDeadline)
            if previous == nil {
                guard counts.owner < 16 else {
                    throw AddonFailure(
                        code  : .resourceDenied,
                        reason: "An addon may retain at most 16 active publications."
                    )
                }
                if admitted.kind == .activity {
                    guard counts.activities < 16, counts.ownerActivities < 4 else {
                        throw AddonFailure(
                            code  : .resourceDenied,
                            reason: "The activity quota is full."
                        )
                    }
                    counts.activities += 1
                    counts.ownerActivities += 1
                } else if admitted.kind == .notice {
                    guard counts.notices < 8 else {
                        throw AddonFailure(
                            code  : .resourceDenied,
                            reason: "The notice quota is full."
                        )
                    }
                    counts.notices += 1
                }
                counts.owner += 1
            }
            let contentBytes = try JSONEncoder().encode(admitted).count
            let additional = contentBytes - (previous?.contentBytes ?? 0)
                + (previous == nil ? Self.recordCharge : 0)
            guard additional <= maximumRetainedBytes - projectedBytes else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The retained publication state budget is exhausted."
                )
            }
            projectedBytes += additional
            proposed[admitted.id] = Record(
                revision       : admitted.revision,
                kind           : admitted.kind,
                sessionDeadline: sessionDeadline,
                publication    : admitted,
                contentBytes   : contentBytes
            )
        }
        for operation in output.operations {
            guard case .endPublication(let id) = operation,
                  var record = proposed[id] ?? records[id], record.publication != nil else { continue }
            projectedBytes -= record.contentBytes
            record.publication = nil
            record.contentBytes = 0
            proposed[id] = record
        }
        var newFamilies: [PublicationID: Publication.Kind] = [:]
        for (id, record) in proposed where records[id] == nil && record.publication != nil {
            newFamilies[id] = record.kind
        }
        var previousLiveDeadlines: [PublicationID: Date] = [:]
        for id in proposed.keys {
            guard let previous = records[id], let publication = previous.publication else { continue }
            previousLiveDeadlines[id] = min(
                previous.sessionDeadline,
                publication.expiresAt
            )
        }
        return PreparedOutput(
            records           : proposed,
            previousLiveDeadlines: previousLiveDeadlines,
            session           : session,
            sequence          : sequence,
            stateRevision     : stateRevision,
            owner             : session.identity.addonID,
            retainedBytesAfter: projectedBytes,
            newFamilies       : newFamilies,
            admission         : PublicationAdmission(
                operations: output.operations,
                completion: output.completion,
                checkpoint: output.checkpoint
            )
        )
    }

    /// Source outputs share the canonical publication sequence, never a new replay domain.
    func validateServiceSourceSequence(connection: PublicationConnection, sequence: UInt64) throws {
        guard !isRevisionExhausted, connection.negotiatedProtocol.minor >= 4 else {
            throw AddonFailure(code: .sessionRevoked, reason: "Source connection is unavailable")
        }
        _ = try sessions.validate(connection: connection, generation: connection.generation, sequence: sequence)
    }

    mutating func commitServiceSourceSequence(connection: PublicationConnection, sequence: UInt64) throws {
        try validateServiceSourceSequence(connection: connection, sequence: sequence)
        let session = try sessions.validate(connection: connection, generation: connection.generation, sequence: sequence)
        sessions.advance(session, sequence: sequence)
        advanceStateRevision()
    }

    /// prepareCompletion validates a completion-only event against its exact provider
    /// session without retaining unrelated publication-state revision authority.
    func prepareCompletion(
        _ output          : ProviderOutput,
        connection        : PublicationConnection,
        generation        : ConnectionGeneration,
        sequence          : UInt64,
        expectedCompletion: CompletionExpectation
    ) throws -> PreparedCompletion {
        guard !isRevisionExhausted else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Publication authority revision is exhausted."
            )
        }
        guard output.publications.isEmpty,
              output.operations.isEmpty,
              output.completion != nil,
              output.checkpoint == nil else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The output is not completion-only."
            )
        }
        let session = try sessions.validate(
            connection: connection,
            generation: generation,
            sequence  : sequence
        )
        try output.validate()
        try output.validateContext(
            authenticatedAddonID: session.identity.addonID,
            expectedCompletion  : expectedCompletion,
            previousRevisions   : [:],
            contentSchemas      : session.connection.negotiatedProtocol.contentSchemas
        )
        return PreparedCompletion(
            session  : session,
            sequence : sequence,
            admission: PublicationAdmission(
                operations: output.operations,
                completion: output.completion,
                checkpoint: output.checkpoint
            )
        )
    }

    /// validatePreparedCompletion rechecks only canonical provider session/sequence
    /// authority, so another provider or an unrelated publication cannot revoke it.
    func validatePreparedCompletion(_ prepared: PreparedCompletion) throws {
        guard !isRevisionExhausted else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "Prepared publication authority changed before commit."
            )
        }
        let current = try sessions.validate(
            connection: prepared.session.connection,
            generation: prepared.session.connection.generation,
            sequence  : prepared.sequence
        )
        guard current.connection == prepared.session.connection else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "Prepared publication session changed before commit."
            )
        }
    }

    /// commitPreparedCompletion advances only the exact provider sequence. Ordinary
    /// publication batches continue to use the global revision-guarded transition.
    mutating func commitPreparedCompletion(
        _ prepared: PreparedCompletion
    ) throws -> PublicationAdmission {
        try validatePreparedCompletion(prepared)
        sessions.advance(
            prepared.session,
            sequence: prepared.sequence
        )
        advanceStateRevision()
        return prepared.admission
    }

    /// validatePreparedOutput rechecks authority and expiry at the caller's final clock sample.
    func validatePreparedOutput(
        _ prepared: PreparedOutput,
        at instant : Date
    ) throws {
        guard !isRevisionExhausted, prepared.stateRevision == stateRevision else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "Prepared publication authority changed before commit."
            )
        }
        let current = try sessions.validate(
            connection: prepared.session.connection,
            generation: prepared.session.connection.generation,
            sequence  : prepared.sequence
        )
        guard current.connection == prepared.session.connection else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "Prepared publication session changed before commit."
            )
        }
        guard instant.timeIntervalSince1970.isFinite,
              prepared.previousLiveDeadlines.values.allSatisfy({ $0 > instant }),
              prepared.records.values.allSatisfy({ record in
                record.sessionDeadline > instant
                    && (record.publication?.expiresAt ?? .distantFuture) > instant
              }) else {
            throw AddonFailure(
                code  : .deadlineExceeded,
                reason: "Prepared publication output expired before commit."
            )
        }
    }

    /// commitPreparedOutput applies publications, ends and sequence in one actor turn.
    mutating func commitPreparedOutput(
        _ prepared: PreparedOutput,
        at instant : Date
    ) throws -> PublicationAdmission {
        try validatePreparedOutput(
            prepared,
            at: instant
        )
        for (id, record) in prepared.records { records[id] = record }
        retainedBytes = prepared.retainedBytesAfter
        sessions.advance(
            prepared.session,
            sequence: prepared.sequence
        )
        advanceStateRevision()
        return prepared.admission
    }

    /// accept is a trusted host composition primitive, not transport ingress.
    /// Admission is transactional: failure leaves the last valid publication untouched.
    mutating func accept(
        _ publication: Publication,
        owner        : AddonID
    ) throws {
        let instant = now()
        var activeCounts = activeCounts(
            owner: owner,
            at   : instant
        )
        try accept(
            publication,
            owner       : owner,
            at          : instant,
            activeCounts: &activeCounts
        )
        advanceStateRevision()
    }

    private mutating func accept(
        _ publication: Publication,
        owner        : AddonID,
        at instant   : Date,
        activeCounts : inout ActiveCounts
    ) throws {
        try publication.validateOwnerAndStructure(owner)
        guard instant.timeIntervalSince1970.isFinite, publication.expiresAt > instant else {
            throw AddonFailure(
                code  : .deadlineExceeded,
                reason: "Publication has expired."
            )
        }
        let previous = records[publication.id]
        try publication.validateRevision(after: previous?.revision)
        if let previous {
            guard let retainedPublication = previous.publication,
                  retainedPublication.expiresAt > instant else {
                throw AddonFailure(
                    code  : .sessionRevoked,
                    reason: "An ended publication requires a new host-negotiated session."
                )
            }
        }
        guard previous == nil || previous?.kind == publication.kind else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "A publication session cannot change its family."
            )
        }
        let duration: TimeInterval = publication.kind == .activity
            ? 8 * 3_600
            : (publication.kind == .notice ? 10 : .infinity)
        let sessionDeadline = previous?.sessionDeadline
            ?? (duration.isFinite ? instant.addingTimeInterval(duration) : .distantFuture)
        guard sessionDeadline > instant else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The publication session has ended."
            )
        }
        let admitted = try publication.capped(at: sessionDeadline)
        if previous == nil {
            guard activeCounts.owner < 16 else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "An addon may retain at most 16 active publications."
                )
            }
            if admitted.kind == .activity {
                guard activeCounts.activities < 16, activeCounts.ownerActivities < 4 else {
                    throw AddonFailure(
                        code  : .resourceDenied,
                        reason: "The activity quota is full."
                    )
                }
            }
            if admitted.kind == .notice, activeCounts.notices >= 8 {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The notice quota is full."
                )
            }
        }
        let contentBytes = try JSONEncoder().encode(admitted).count
        let additional = contentBytes
            - (previous?.contentBytes ?? 0)
            + (previous == nil ? Self.recordCharge : 0)
        guard additional <= maximumRetainedBytes - retainedBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The retained publication state budget is exhausted."
            )
        }
        records[admitted.id] = Record(
            revision       : admitted.revision,
            kind           : admitted.kind,
            sessionDeadline: sessionDeadline,
            publication    : admitted,
            contentBytes   : contentBytes
        )
        retainedBytes += additional
        if previous == nil {
            activeCounts.owner += 1
            if admitted.kind == .activity {
                activeCounts.activities      += 1
                activeCounts.ownerActivities += 1
            } else if admitted.kind == .notice {
                activeCounts.notices += 1
            }
        }
    }

    /// accept commits a trusted host batch as one synchronous operation. The bounded
    /// undo list holds affected records, original replay history and charge. Transport
    /// callers must enter through acceptPublicationState instead.
    mutating func accept(
        _ publications: [Publication],
        owner         : AddonID
    ) throws {
        guard publications.count <= 16,
              Set(publications.map(\.id)).count == publications.count else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "A batch requires at most 16 distinct publications."
            )
        }
        let instant = now()
        var activeCounts = activeCounts(
            owner: owner,
            at   : instant
        )
        let previous = publications.map { ($0.id, records[$0.id]) }
        let previousBytes = retainedBytes
        do {
            for publication in publications {
                try accept(
                    publication,
                    owner       : owner,
                    at          : instant,
                    activeCounts: &activeCounts
                )
            }
        } catch {
            for (id, record) in previous {
                records[id] = record
            }
            retainedBytes = previousBytes
            throw error
        }
        advanceStateRevision()
    }

    private func activeCounts(
        owner     : AddonID,
        at instant: Date
    ) -> ActiveCounts {
        var counts = ActiveCounts()
        for (id, record) in records {
            guard let publication = record.publication,
                  publication.expiresAt > instant else { continue }
            if id.addonID == owner {
                counts.owner += 1
            }
            if record.kind == .activity {
                counts.activities += 1
                if id.addonID == owner {
                    counts.ownerActivities += 1
                }
            } else if record.kind == .notice {
                counts.notices += 1
            }
        }
        return counts
    }

    /// snapshot selects due entries and preserves pending timelines without a timer or
    /// provider tick. Missing identities mean revoked or expired, never merely waiting.
    func snapshot(at date: Date) -> [Publication] {
        guard date.timeIntervalSince1970.isFinite else { return [] }
        return records.values.compactMap { record in
            guard let publication = record.publication,
                  date < publication.expiresAt else { return nil }
            return publication.presentation(at: date)
        }.sorted { $0.id.stableKey < $1.id.stableKey }
    }

    func nextDeadline(after date: Date) -> Date? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return records.values.compactMap(\.publication).flatMap { publication in
            [publication.expiresAt] + (publication.timeline ?? []).map(\.date)
        }.filter { $0 > date }.min()
    }

    /// publication returns canonical retained content without presentation projection.
    func publication(
        id     : PublicationID,
        at date: Date
    ) -> Publication? {
        guard date.timeIntervalSince1970.isFinite,
              let publication = records[id]?.publication,
              publication.expiresAt > date else { return nil }
        return publication
    }

    /// recordAccounting reports the owning component's exact retained charge.
    func recordAccounting(id: PublicationID) -> RecordAccounting? {
        guard let record = records[id] else { return nil }
        return RecordAccounting(
            owner         : id.addonID,
            revision      : record.revision,
            kind          : record.kind,
            contentBytes  : record.contentBytes,
            tombstoneBytes: Self.recordCharge
        )
    }

    /// removeHistory removes one inactive tombstone after runtime bindings no longer reference it.
    mutating func removeHistory(id: PublicationID) {
        guard let record = records[id], record.publication == nil else { return }
        records.removeValue(forKey: id)
        retainedBytes -= Self.recordCharge
        advanceStateRevision()
    }

    /// sessionAccounting reports connection and namespace charges from their owner.
    func sessionAccounting(owner: AddonID) -> PublicationSessionRegistry.Accounting {
        sessions.accounting(owner: owner)
    }

    /// remove ends this session without permitting its revision to be replayed.
    mutating func remove(
        id   : PublicationID,
        owner: AddonID
    ) throws {
        try id.validateOwner(owner)
        discardContent(id: id)
        advanceStateRevision()
    }

    /// remove revokes all connection authority before clearing this owner's future
    /// entries and replay metadata in the same synchronous mutation.
    mutating func remove(owner: AddonID) {
        retainedBytes -= sessions.remove(owner: owner)
        for id in records.keys.filter({ $0.addonID == owner }) {
            if let record = records.removeValue(forKey: id) {
                retainedBytes -= Self.recordCharge + record.contentBytes
            }
        }
        advanceStateRevision()
    }

    /// expire makes expiry terminal even for retainMarked, which only describes a stale
    /// but unexpired snapshot after an unexpected provider failure.
    mutating func expire(at date: Date) {
        guard date.timeIntervalSince1970.isFinite else { return }
        let expired = records.keys.filter({
            records[$0]?.publication?.expiresAt ?? .distantFuture <= date
        })
        for id in expired {
            discardContent(id: id)
        }
        if !expired.isEmpty { advanceStateRevision() }
    }

    private mutating func discardContent(id: PublicationID) {
        guard var record = records[id], record.publication != nil else { return }
        retainedBytes -= record.contentBytes
        record.contentBytes = 0
        record.publication  = nil
        records[id] = record
    }

    private mutating func advanceStateRevision() {
        // Value copies can take different transitions to the same numeric revision.
        // Refresh restoration authority so those branches cannot exchange proposals.
        restorationIssuer = UUID()
        guard stateRevision < UInt64.max else {
            isRevisionExhausted = true
            return
        }
        stateRevision += 1
    }
}

extension PublicationState {
    /// PreparedRestoration borrows validated canonical records without granting live authority.
    /// Its owner/revision guard and final clock check must succeed before synchronous commit.
    struct PreparedRestoration: Sendable {
        fileprivate let issuer        : UUID
        fileprivate let stateRevision : UInt64
        fileprivate let preparedAt    : Date
        fileprivate let records       : [PublicationID: Record]
        fileprivate let namespace     : PublicationSessionRegistry.NamespaceBinding
        let owner                     : AddonID
        let additionalBytes           : Int
        let namespaceBytes            : Int
        let retainedBytesAfter        : Int
        let newFamilies               : [PublicationID: Publication.Kind]

        /// forEachRestoredPublication visits complete admitted content, including future entries.
        /// Expired members were converted to terminal records during preparation and are omitted.
        func forEachRestoredPublication(_ visit: (Publication) throws -> Void) rethrows {
            for record in records.values {
                if let publication = record.publication { try visit(publication) }
            }
        }

        /// forEachTerminalPublicationID visits both archived tombstones and elapsed content.
        func forEachTerminalPublicationID(_ visit: (PublicationID) throws -> Void) rethrows {
            for (id, record) in records where record.publication == nil {
                try visit(id)
            }
        }
    }

    /// forEachArchivedRecord visits retained owner history without projecting timelines or mutating state.
    /// Capture cannot reconstruct already-pruned history. Expiry emits terminal history; notices
    /// are never archived. The caller prepays any arrays, encoding or borrowed-content retention.
    func forEachArchivedRecord(
        owner: AddonID,
        at date: Date,
        _ visit: (PublicationArchiveRecord) throws -> Void
    ) throws {
        guard date.timeIntervalSince1970.isFinite else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Archive capture requires a finite clock."
            )
        }
        for (id, record) in records where id.addonID == owner && record.kind != .notice {
            let publication = record.publication.flatMap {
                $0.expiresAt > date && record.sessionDeadline > date ? $0 : nil
            }
            try visit(PublicationArchiveRecord(
                id             : id,
                revision       : record.revision,
                kind           : record.kind,
                sessionDeadline: record.sessionDeadline,
                publication    : publication
            ))
        }
    }

    /// restorationMetadataBytes quotes record and namespace growth without creating proposal tables.
    /// The caller separately prepays content bytes computed under its protected graph scope.
    func restorationMetadataBytes(
        recordCount: Int,
        identity   : VerifiedAddonIdentity
    ) throws -> Int {
        guard !isRevisionExhausted, recordCount >= 0 else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Restoration metadata requires available state authority and a valid count."
            )
        }
        let namespace = try sessions.prepareNamespace(
            identity      : identity,
            availableBytes: maximumRetainedBytes - retainedBytes
        )
        let available = maximumRetainedBytes - retainedBytes - namespace.additionalBytes
        guard recordCount <= available / Self.recordCharge else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Restoration record metadata exceeds the retained-state budget."
            )
        }
        return namespace.additionalBytes + recordCount * Self.recordCharge
    }

    /// prepareRestoration validates all records and namespace growth without changing authority.
    /// Input/proposal retention is prepaid by the host. Record count follows retained metadata,
    /// independently of active-family limits or the runtime's separate assignment capacity.
    func prepareRestoration(
        _ archived: [PublicationArchiveRecord],
        identity  : VerifiedAddonIdentity,
        at date   : Date
    ) throws -> PreparedRestoration {
        guard !isRevisionExhausted, date.timeIntervalSince1970.isFinite else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Restoration requires a finite clock and available state authority."
            )
        }
        let namespace = try sessions.prepareNamespace(
            identity      : identity,
            availableBytes: maximumRetainedBytes - retainedBytes
        )
        let availableRecordBytes = maximumRetainedBytes - retainedBytes - namespace.additionalBytes
        guard archived.count <= availableRecordBytes / Self.recordCharge else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The retained publication record capacity is exhausted."
            )
        }
        var proposed: [PublicationID: Record] = [:]
        var newFamilies: [PublicationID: Publication.Kind] = [:]
        var projectedBytes = retainedBytes + namespace.additionalBytes
        var counts = activeCounts(
            owner: identity.addonID,
            at   : date
        )
        for archivedRecord in archived {
            try archivedRecord.id.validateOwner(identity.addonID)
            guard archivedRecord.kind != .notice,
                  archivedRecord.sessionDeadline.timeIntervalSince1970.isFinite,
                  records[archivedRecord.id] == nil,
                  proposed[archivedRecord.id] == nil else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Restoration contains a prohibited, colliding or malformed record."
                )
            }
            var content: Publication?
            var contentBytes = 0
            if let publication = archivedRecord.publication {
                try publication.validateOwnerAndStructure(identity.addonID)
                guard publication.id == archivedRecord.id,
                      publication.revision == archivedRecord.revision,
                      publication.kind == archivedRecord.kind,
                      publication.expiresAt <= archivedRecord.sessionDeadline else {
                    throw AddonFailure(
                        code  : .invalidPayload,
                        reason: "Archived publication content does not match its canonical record."
                    )
                }
                if publication.expiresAt > date && archivedRecord.sessionDeadline > date {
                    guard counts.owner < 16 else {
                        throw AddonFailure(
                            code  : .resourceDenied,
                            reason: "An addon may retain at most 16 active publications."
                        )
                    }
                    if publication.kind == .activity {
                        guard counts.activities < 16, counts.ownerActivities < 4 else {
                            throw AddonFailure(
                                code  : .resourceDenied,
                                reason: "The activity quota is full."
                            )
                        }
                        counts.activities += 1
                        counts.ownerActivities += 1
                    }
                    counts.owner += 1
                    content = publication
                    contentBytes = try JSONEncoder().encode(publication).count
                }
            }
            guard Self.recordCharge <= maximumRetainedBytes - projectedBytes,
                  contentBytes <= maximumRetainedBytes - projectedBytes - Self.recordCharge else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The retained publication state budget is exhausted."
                )
            }
            projectedBytes += Self.recordCharge + contentBytes
            proposed[archivedRecord.id] = Record(
                revision       : archivedRecord.revision,
                kind           : archivedRecord.kind,
                sessionDeadline: archivedRecord.sessionDeadline,
                publication    : content,
                contentBytes   : contentBytes
            )
            if content != nil { newFamilies[archivedRecord.id] = archivedRecord.kind }
        }
        return PreparedRestoration(
            issuer            : restorationIssuer,
            stateRevision     : stateRevision,
            preparedAt        : date,
            records           : proposed,
            namespace         : namespace,
            owner             : identity.addonID,
            additionalBytes   : projectedBytes - retainedBytes,
            namespaceBytes    : namespace.additionalBytes,
            retainedBytesAfter: projectedBytes,
            newFamilies       : newFamilies
        )
    }

    /// validatePreparedRestoration checks the final host clock and exact issuing state revision.
    /// A newly expired proposal must be prepared again as terminal history. Clock rollback
    /// also rejects, because earlier time could reactivate families absent from the quota quote.
    func validatePreparedRestoration(
        _ prepared: PreparedRestoration,
        at date   : Date
    ) throws {
        guard !isRevisionExhausted,
              prepared.issuer == restorationIssuer,
              prepared.stateRevision == stateRevision else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "Prepared restoration authority changed before commit."
            )
        }
        guard date.timeIntervalSince1970.isFinite, date >= prepared.preparedAt,
              prepared.records.values.allSatisfy({ record in
                guard let publication = record.publication else { return true }
                return publication.expiresAt > date && record.sessionDeadline > date
              }) else {
            throw AddonFailure(
                code  : .deadlineExceeded,
                reason: "Prepared restoration expired or the final clock moved backwards."
            )
        }
    }

    /// commitPreparedRestoration installs namespace and records in one nonthrowing transition.
    /// The host must call final validation and commit with no intervening suspension or state
    /// mutation, after reserving all record, family and associated asset resources.
    mutating func commitPreparedRestoration(_ prepared: PreparedRestoration) {
        precondition(
            !isRevisionExhausted
                && prepared.issuer == restorationIssuer
                && prepared.stateRevision == stateRevision
        )
        sessions.bindNamespace(prepared.namespace)
        for (id, record) in prepared.records { records[id] = record }
        retainedBytes = prepared.retainedBytesAfter
        advanceStateRevision()
    }
}
