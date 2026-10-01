//
//  ProtocolAdmissionTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct ProtocolAdmissionTests {

    private let instant = Date(timeIntervalSince1970: 2_000_000_000)

    private func identity(
        _ name   : String = "focus",
        publisher: String = "publisher"
    ) throws -> VerifiedAddonIdentity {
        VerifiedAddonIdentity(
            publisher: publisher,
            addonID  : try #require(AddonID(rawValue: "com.example.\(name)"))
        )
    }

    private func identifier(_ identity: VerifiedAddonIdentity) -> PublicationID {
        PublicationID(
            addonID   : identity.addonID,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    private func store(
        bytes      : Int = PublicationStore.maximumStateBytes,
        connections: Int = 32,
        publishers : Int = 256
    ) -> PublicationStore {
        PublicationStore(
            maximumRetainedBytes      : bytes,
            maximumConnections        : connections,
            maximumPublisherNamespaces: publishers,
            now                       : { Date(timeIntervalSince1970: 2_000_000_000) }
        )
    }

    private func offer(
        _ schemas: [Int] = [1],
        major    : Int = 1,
        minimum  : Int = 0
    ) throws -> ProtocolOffer {
        try ProtocolOffer(
            major         : major,
            minimumMinor  : minimum,
            maximumMinor  : 10,
            contentSchemas: schemas
        )
    }

    private func connect(
        _ store : PublicationStore,
        identity: VerifiedAddonIdentity,
        ids     : [PublicationID],
        schemas : [Int] = [1],
        digest  : String = "digest"
    ) async throws -> PublicationConnection {
        try await store.openConnection(
            identity              : identity,
            verifiedDigest        : digest,
            manifestProtocol      : ProtocolVersion(major: 1, minimumMinor: 0),
            offer                 : offer(schemas),
            authorizedPublications: ids
        )
    }

    private func content(
        schema        : Int = 1,
        representation: Int = 0,
        lights        : [GlassLight]? = nil,
        text          : String = "Focus"
    ) throws -> PresentationSet {
        let plain = try ContentDocument(
            root              : .text(text),
            privacy           : .publicContent,
            accessibilityLabel: "Focus"
        )

        let selected = try ContentDocument(
            schemaVersion     : schema,
            root              : .text(text),
            privacy           : .publicContent,
            accessibilityLabel: "Focus",
            glassLights       : lights
        )

        return try PresentationSet(
            widget         : representation == 0 ? selected : plain,
            compactLeading : representation == 1 ? selected : nil,
            compactTrailing: representation == 2 ? selected : nil,
            minimal        : representation == 3 ? selected : nil,
            expanded       : representation == 4 ? selected : nil
        )
    }

    private func publication(
        _ id          : PublicationID,
        revision      : UInt64 = 1,
        schema        : Int = 1,
        representation: Int = 0,
        future        : Bool = false,
        lights        : [GlassLight]? = nil,
        text          : String = "Focus"
    ) throws -> Publication {
        let presentation = try content(
            schema        : schema,
            representation: representation,
            lights        : lights,
            text          : text
        )

        return try Publication(
            id         : id,
            revision   : revision,
            kind       : .widget,
            content    : future ? nil : presentation,
            timeline   : future ? [ScheduledEntry(date: instant.addingTimeInterval(10), content: presentation)] : nil,
            expiresAt  : instant.addingTimeInterval(60),
            stalePolicy: .remove
        )
    }

    private func output(
        _ publications: [Publication] = [],
        operations    : [OperationRequest] = [],
        completion    : InvocationCompletion? = nil,
        checkpoint    : Data? = nil
    ) throws -> ProviderOutput {
        try ProviderOutput(
            schemaVersion: 1,
            publications : publications,
            operations   : operations,
            completion   : completion,
            checkpoint   : checkpoint
        )
    }

    @discardableResult
    private func admit(
        _ store     : PublicationStore,
        connection  : PublicationConnection,
        sequence    : UInt64 = 1,
        publications: [Publication] = [],
        operations  : [OperationRequest] = [],
        completion  : InvocationCompletion? = nil,
        expectation : CompletionExpectation? = nil,
        checkpoint  : Data? = nil,
        generation  : ConnectionGeneration? = nil
    ) async throws -> PublicationAdmission {
        try await store.acceptPublicationState(
            output(publications, operations: operations, completion: completion, checkpoint: checkpoint),
            connection        : connection,
            generation        : generation ?? connection.generation,
            sequence          : sequence,
            expectedCompletion: expectation
        )
    }

    @Test
    func negotiationIntersectsInStableOrderWithoutInventingSchemas() throws {
        let requirement = try ProtocolVersion(major: 1, minimumMinor: 0)
        let negotiated  = try ProtocolNegotiator.negotiate(
            offer           : offer([65_535, 2, 1]),
            manifestProtocol: requirement
        )

        #expect(negotiated.major == 1)
        #expect(negotiated.minor == 0)
        #expect(negotiated.contentSchemas == [1, 2])
        #expect(
            try ProtocolNegotiator.negotiate(offer: offer([2]), manifestProtocol: requirement).contentSchemas == [2]
        )
        #expect(try ProtocolNegotiator.negotiate(
            offer           : offer([2, 1]),
            manifestProtocol: requirement,
            contentSchemas  : [2]
        ).contentSchemas == [2])

        for incompatible in [try offer([1], major: 2), try offer([1], minimum: 1), try offer([3])] {
            #expect(throws: AddonFailure.self) {
                try ProtocolNegotiator.negotiate(offer: incompatible, manifestProtocol: requirement)
            }
        }

        #expect(throws: AddonFailure.self) {
            try ProtocolNegotiator.negotiate(
                offer           : offer(),
                manifestProtocol: ProtocolVersion(major: 1, minimumMinor: 1)
            )
        }

        for policy in [[], [4], [1, 4], [1, 1]] {
            #expect(throws: AddonFailure.self) {
                try ProtocolNegotiator.negotiate(
                    offer           : offer(),
                    manifestProtocol: requirement,
                    contentSchemas  : policy
                )
            }
        }

        #expect(throws: AddonFailure.self) {
            try ProtocolNegotiator.negotiate(
                offer           : offer([2]),
                manifestProtocol: requirement,
                contentSchemas  : [1]
            )
        }
    }

    @Test
    func schemaThreeRequiresInstalledFileWorkspaceRenderer() throws {
        let requirement      = try ProtocolVersion(major: 1, minimumMinor: 0)
        let schemaThreeOffer = try offer([3, 2, 1])

        #expect(throws: AddonFailure.self) {
            try ProtocolNegotiator.negotiate(
                offer           : schemaThreeOffer,
                manifestProtocol: requirement,
                contentSchemas  : [1, 2, 3]
            )
        }

        let negotiated = try ProtocolNegotiator.negotiate(
            offer                       : schemaThreeOffer,
            manifestProtocol            : requirement,
            contentSchemas              : [1, 2, 3],
            supportsFileWorkspaceContent: true
        )

        #expect(negotiated.contentSchemas == [1, 2, 3])
    }

    @Test
    func conservativeContextChecksEveryRepresentationAndFutureEntry() throws {
        let owner = try identity()
        let id    = identifier(owner)
        try output([publication(id)]).validateContext(
            authenticatedAddonID: owner.addonID,
            expectedCompletion  : nil,
            previousRevisions   : [:]
        )

        for future in [false, true] {
            for representation in 0...4 {
                for lights: [GlassLight]? in [nil, []] {
                    let value = try output(
                        [publication(id, schema: 2, representation: representation, future: future, lights: lights)]
                    )

                    #expect(throws: AddonFailure.self) {
                        try value.validateContext(
                            authenticatedAddonID: owner.addonID,
                            expectedCompletion  : nil,
                            previousRevisions   : [:]
                        )
                    }

                    try value.validateContext(
                        authenticatedAddonID: owner.addonID,
                        expectedCompletion  : nil,
                        previousRevisions   : [:],
                        contentSchemas      : [2, 1]
                    )
                }
            }
        }

        for policy in [[], [4], [1, 4], [1, 1]] {
            #expect(throws: AddonFailure.self) {
                try output().validateContext(
                    authenticatedAddonID: owner.addonID,
                    expectedCompletion  : nil,
                    previousRevisions   : [:],
                    contentSchemas      : policy
                )
            }
        }
    }

    @Test
    func schemaRejectionLeavesBatchBytesRevisionsAndSequenceUntouched() async throws {
        let owner      = try identity()
        let ids        = [identifier(owner), identifier(owner)]
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : ids
        )

        let first = try publication(ids[0])
        try await admit(
            store,
            connection  : connection,
            publications: [first]
        )

        let bytes  = await store.retainedBytes
        let update = try publication(
            ids[0],
            revision: 2,
            text    : "Updated"
        )

        for future in [false, true] {
            await #expect(throws: AddonFailure.self) {
                try await admit(
                    store,
                    connection  : connection,
                    sequence    : 2,
                    publications: [update, publication(ids[1], schema: 2, future: future)]
                )
            }

            #expect(await store.snapshot(at: instant) == [first])
            #expect(await store.retainedBytes == bytes)
        }

        try await admit(
            store,
            connection  : connection,
            sequence    : 2,
            publications: [update]
        )

        #expect(await store.snapshot(at: instant) == [update])
    }

    @Test
    func explicitSchemaTwoPreservesLightsAndReturnsUnexecutedOperations() async throws {
        let owner      = try identity()
        let id         = identifier(owner)
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : [id],
            schemas : [2]
        )

        let lights = [try GlassLight(x: 0.3, y: 0.7, radius: 0.4, red: 1, green: 0.25, blue: 0.1, intensity: 0.5)]
        let value  = try publication(
            id,
            schema: 2,
            lights: lights
        )

        let requestID  = UUID()
        let completion = InvocationCompletion.action(
            requestID: requestID,
            outcome  : .completed(payload: Data([1]))
        )

        let result = try await admit(
            store,
            connection  : connection,
            publications: [value],
            operations  : [.endPublication(id)],
            completion  : completion,
            expectation : .action(requestID: requestID),
            checkpoint  : Data([4, 5])
        )

        #expect(await store.snapshot(at: instant) == [value])
        #expect(await store.snapshot(at: instant).first?.content?.widget?.glassLights == lights)
        #expect(result.operations == [.endPublication(id)])
        #expect(result.completion == completion)
        #expect(result.checkpoint == Data([4, 5]))
    }

    @Test
    func hostAssignmentsRejectForeignAddonInstanceSessionAndEndOperations() async throws {
        let owner      = try identity()
        let id         = identifier(owner)
        let foreign    = try identity("other")
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : [id]
        )

        let first = try publication(id)
        try await admit(
            store,
            connection  : connection,
            publications: [first]
        )

        let bytes      = await store.retainedBytes
        let unassigned = [
            identifier(foreign),
            PublicationID(addonID: owner.addonID, instanceID: UUID(), sessionID: id.sessionID),
            PublicationID(addonID: owner.addonID, instanceID: id.instanceID, sessionID: UUID())
        ]

        for invalid in unassigned {
            await #expect(throws: AddonFailure.self) {
                try await admit(
                    store,
                    connection  : connection,
                    sequence    : 2,
                    publications: [publication(id, revision: 2), publication(invalid)]
                )
            }

            await #expect(throws: AddonFailure.self) {
                try await admit(
                    store,
                    connection  : connection,
                    sequence    : 2,
                    publications: [publication(id, revision: 2)],
                    operations  : [.endPublication(invalid)]
                )
            }

            #expect(await store.snapshot(at: instant) == [first])
            #expect(await store.retainedBytes == bytes)
        }

        try await admit(
            store,
            connection  : connection,
            sequence    : 2,
            publications: [publication(id, revision: 2)]
        )
    }

    @Test
    func invalidCompletionDoesNotConsumeSequenceOrRevision() async throws {
        let owner      = try identity()
        let id         = identifier(owner)
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : [id]
        )

        let first = try publication(id)
        try await admit(
            store,
            connection  : connection,
            publications: [first]
        )

        let bytes      = await store.retainedBytes
        let request    = UUID()
        let completion = InvocationCompletion.action(requestID: request, outcome: .outcomeUnknown)
        for expectation: CompletionExpectation? in [nil, .action(requestID: UUID())] {
            await #expect(throws: AddonFailure.self) {
                try await admit(
                    store,
                    connection  : connection,
                    sequence    : 2,
                    publications: [publication(id, revision: 2)],
                    completion  : completion,
                    expectation : expectation
                )
            }

            #expect(await store.retainedBytes == bytes)
            #expect(await store.snapshot(at: instant) == [first])
        }

        try await admit(
            store,
            connection  : connection,
            sequence    : 2,
            publications: [publication(id, revision: 2)],
            completion  : completion,
            expectation : .action(requestID: request)
        )
    }

    @Test
    func reconnectRevokesOldAuthorityButRetainsCurrentFutureAndRevisions() async throws {
        let owner = try identity()
        let ids   = [identifier(owner), identifier(owner)]
        let store = store()
        let old   = try await connect(
            store,
            identity: owner,
            ids     : ids
        )

        let first  = try publication(ids[0])
        let future = try publication(ids[1], future: true)
        try await admit(
            store,
            connection  : old,
            publications: [first, future]
        )

        let snapshot       = await store.snapshot(at: instant)
        let futureSnapshot = await store.snapshot(at: instant.addingTimeInterval(11))
        await store.closeConnection(old)
        #expect(await store.snapshot(at: instant) == snapshot)
        #expect(await store.snapshot(at: instant.addingTimeInterval(11)) == futureSnapshot)

        let fresh = try await connect(
            store,
            identity: owner,
            ids     : ids,
            digest  : "new-digest"
        )

        #expect(fresh.generation != old.generation)

        await #expect(throws: AddonFailure.self) {
            try await admit(
                store,
                connection  : old,
                sequence    : 2,
                publications: [publication(ids[0], revision: 2)]
            )
        }

        await #expect(throws: AddonFailure.self) {
            try await admit(
                store,
                connection: fresh,
                generation: old.generation
            )
        }

        await #expect(throws: AddonFailure.self) { try await admit(store, connection: fresh, publications: [first]) }
        try await admit(
            store,
            connection  : fresh,
            publications: [publication(ids[0], revision: 2)]
        )

        await store.closeConnection(old)
        try await admit(
            store,
            connection: fresh,
            sequence  : 2
        )

        await store.remove(owner: owner.addonID)
        #expect(await store.snapshot(at: instant.addingTimeInterval(11)).isEmpty)
        #expect(await store.retainedBytes == 0)

        await #expect(throws: AddonFailure.self) {
            try await admit(
                store,
                connection  : fresh,
                sequence    : 3,
                publications: [publication(ids[0], revision: 3)]
            )
        }
    }

    @Test
    func sequenceIsNonzeroStrictAndCannotWrap() async throws {
        let owner      = try identity()
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : []
        )

        await #expect(throws: AddonFailure.self) { try await admit(store, connection: connection, sequence: 0) }
        try await admit(
            store,
            connection: connection,
            sequence  : 2
        )

        for sequence: UInt64 in [1, 2] {
            await #expect(throws: AddonFailure.self) {
                try await admit(
                    store,
                    connection: connection,
                    sequence  : sequence
                )
            }
        }

        try await admit(
            store,
            connection: connection,
            sequence  : .max
        )

        await #expect(throws: AddonFailure.self) { try await admit(store, connection: connection, sequence: .max) }
        await #expect(throws: AddonFailure.self) { try await admit(store, connection: connection, sequence: 1) }
    }

    @Test
    func failedReplacementPreservesExistingAuthorityAndSuccessfulReplacementHasNoGrowth() async throws {
        let owner      = try identity()
        let id         = identifier(owner)
        let store      = store(connections: 1, publishers: 1)
        var connection = try await connect(
            store,
            identity: owner,
            ids     : [id]
        )

        let baseline = await store.retainedBytes
        for incompatible in [try offer([3]), try offer([1], major: 2), try offer([1], minimum: 1)] {
            await #expect(throws: AddonFailure.self) {
                try await store.openConnection(
                    identity              : owner,
                    verifiedDigest        : "replacement",
                    manifestProtocol      : ProtocolVersion(major: 1, minimumMinor: 0),
                    offer                 : incompatible,
                    authorizedPublications: [id]
                )
            }

            #expect(await store.retainedBytes == baseline)
        }

        await #expect(throws: AddonFailure.self) {
            try await store.openConnection(
                identity              : owner,
                verifiedDigest        : "replacement",
                manifestProtocol      : ProtocolVersion(major: 1, minimumMinor: 1),
                offer                 : offer(),
                authorizedPublications: [id]
            )
        }

        try await admit(store, connection: connection)
        for index in 0..<3 {
            let previous = connection
            connection   = try await connect(
                store,
                identity: owner,
                ids     : [id],
                digest  : "digest-\(index)"
            )

            #expect(connection.generation != previous.generation)
            #expect(await store.retainedBytes == baseline)

            await #expect(throws: AddonFailure.self) { try await admit(store, connection: previous, sequence: 2) }
            try await admit(store, connection: connection)
        }
    }

    @Test
    func namespacePublisherBindingSurvivesCloseUntilExplicitOwnerRemoval() async throws {
        let owner      = try identity()
        let collision  = try identity(publisher: "other-publisher")
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : []
        )

        await #expect(throws: AddonFailure.self) { try await connect(store, identity: collision, ids: []) }
        await store.closeConnection(connection)
        #expect(await store.retainedBytes == 1_024)

        await #expect(throws: AddonFailure.self) { try await connect(store, identity: collision, ids: []) }
        await store.remove(owner: owner.addonID)
        let rebound = try await connect(
            store,
            identity: collision,
            ids     : []
        )

        await #expect(throws: AddonFailure.self) { try await admit(store, connection: connection) }
        try await admit(store, connection: rebound)
    }

    @Test
    func connectionMetadataAndCountCapacityIsChargedBeforeInsertion() async throws {
        let owner    = try identity()
        let other    = try identity("other")
        let tooSmall = store(bytes: 5_119)
        await #expect(throws: AddonFailure.self) { try await connect(tooSmall, identity: owner, ids: []) }
        #expect(await tooSmall.retainedBytes == 0)

        let exact      = store(bytes: 5_120)
        let connection = try await connect(
            exact,
            identity: owner,
            ids     : []
        )

        #expect(await exact.retainedBytes == 5_120)

        await #expect(throws: AddonFailure.self) { try await connect(exact, identity: other, ids: []) }
        try await admit(exact, connection: connection)
        await exact.closeConnection(connection)
        #expect(await exact.retainedBytes == 1_024)

        _ = try await connect(
            exact,
            identity: owner,
            ids     : []
        )

        await exact.remove(owner: owner.addonID)
        #expect(await exact.retainedBytes == 0)

        for limited in [store(connections: 1), store(publishers: 1)] {
            let first = try await connect(
                limited,
                identity: owner,
                ids     : []
            )

            await #expect(throws: AddonFailure.self) { try await connect(limited, identity: other, ids: []) }
            try await admit(limited, connection: first)
        }

        let namespaces = store(publishers: 1)
        let first      = try await connect(
            namespaces,
            identity: owner,
            ids     : []
        )

        await namespaces.closeConnection(first)
        await #expect(throws: AddonFailure.self) { try await connect(namespaces, identity: other, ids: []) }
        let disabled = store(connections: 0)
        await #expect(throws: AddonFailure.self) { try await connect(disabled, identity: owner, ids: []) }
    }

    @Test
    func quotaFailureRollsBackWholeBatchAndPreservesUnrelatedOwner() async throws {
        let owner      = try identity()
        let other      = try identity("other")
        let ids        = [identifier(owner), identifier(owner)]
        let otherID    = identifier(other)
        let store      = store(bytes: 16_000)
        let connection = try await connect(
            store,
            identity: owner,
            ids     : ids
        )

        let otherConnection = try await connect(
            store,
            identity: other,
            ids     : [otherID]
        )

        try await admit(
            store,
            connection  : connection,
            publications: [publication(ids[0])]
        )

        try await admit(
            store,
            connection  : otherConnection,
            publications: [publication(otherID)]
        )

        let snapshot = await store.snapshot(at: instant)
        let bytes    = await store.retainedBytes
        await #expect(throws: AddonFailure.self) {
            try await admit(
                store,
                connection  : connection,
                sequence    : 2,
                publications: [
                    publication(ids[0], revision: 2),
                    publication(ids[1], text: String(repeating: "x", count: 4_000))
                ]
            )
        }

        #expect(await store.snapshot(at: instant) == snapshot)
        #expect(await store.retainedBytes == bytes)

        try await admit(
            store,
            connection  : connection,
            sequence    : 2,
            publications: [publication(ids[0], revision: 2)]
        )

        try await admit(
            store,
            connection: otherConnection,
            sequence  : 2
        )

        await store.remove(owner: owner.addonID)
        #expect(await store.snapshot(at: instant).map(\.id) == [otherID])

        try await admit(
            store,
            connection: otherConnection,
            sequence  : 3
        )

        await store.remove(owner: other.addonID)
        #expect(await store.retainedBytes == 0)
    }

    @Test
    func hostInputsAreBoundedAndFailedGrantsDoNotReplaceConnection() async throws {
        let owner      = try identity()
        let id         = identifier(owner)
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : [id]
        )

        let bytes = await store.retainedBytes
        for ids in [[id, id], (0..<17).map { _ in identifier(owner) }, [identifier(try identity("other"))]] {
            await #expect(throws: AddonFailure.self) { try await connect(store, identity: owner, ids: ids) }
        }

        for digest in ["", String(repeating: "é", count: 257)] {
            await #expect(throws: AddonFailure.self) {
                try await connect(
                    store,
                    identity: owner,
                    ids     : [],
                    digest  : digest
                )
            }
        }

        for publisher in ["", String(repeating: "é", count: 257)] {
            await #expect(throws: AddonFailure.self) {
                try await connect(
                    store,
                    identity: identity("invalid", publisher: publisher),
                    ids     : []
                )
            }
        }

        #expect(await store.retainedBytes == bytes)

        try await admit(
            store,
            connection  : connection,
            publications: [publication(id)]
        )

        let otherStore = self.store()
        await #expect(throws: AddonFailure.self) { try await admit(otherStore, connection: connection) }
    }

    @Test
    func endedSessionCannotBeRevivedThroughNewConnection() async throws {
        let owner      = try identity()
        let id         = identifier(owner)
        let store      = store()
        let connection = try await connect(
            store,
            identity: owner,
            ids     : [id]
        )

        try await admit(
            store,
            connection  : connection,
            publications: [publication(id)]
        )

        try await store.remove(id: id, owner: owner.addonID)
        await store.closeConnection(connection)
        let fresh = try await connect(
            store,
            identity: owner,
            ids     : [id]
        )

        await #expect(throws: AddonFailure.self) {
            try await admit(
                store,
                connection  : fresh,
                publications: [publication(id, revision: 2)]
            )
        }

        #expect(await store.snapshot(at: instant).isEmpty)

        try await admit(store, connection: fresh)
    }
}
