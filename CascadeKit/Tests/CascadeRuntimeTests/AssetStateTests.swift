//
//  AssetStateTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AssetStateTests {

    private let owner: AddonID
    private let now   = Date(timeIntervalSince1970: 2_000_000_000)

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.assets"))
    }

    private func scope(
        id       : PublicationID? = nil,
        token    : UUID = UUID(),
        publisher: String = "test.publisher",
        digest   : String = "test-digest",
        feature  : String = "widget"
    ) -> AssetState.Scope {
        AssetState.Scope(
            identity       : VerifiedAddonIdentity(publisher: publisher, addonID: owner),
            verifiedDigest : digest,
            featureID      : feature,
            publicationID  : id
                ?? PublicationID(
                    addonID   : owner,
                    instanceID: UUID(),
                    sessionID : UUID()
                ),
            connectionToken: token
        )
    }

    private func content(
        _ ids  : [String],
        privacy: ContentDocument.Privacy = .publicContent
    ) throws -> PresentationSet {
        try PresentationSet(
            widget         : ContentDocument(
                root              : .text("Ready"),
                privacy           : privacy,
                accessibilityLabel: "Ready",
                assetIDs          : ids
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    private func publication(
        _ scope : AssetState.Scope,
        ids     : [String],
        revision: UInt64 = 1,
        timeline: [ScheduledEntry]? = nil
    ) throws -> Publication {
        try Publication(
            id         : scope.publicationID,
            revision   : revision,
            kind       : .widget,
            content    : timeline == nil ? content(ids) : nil,
            timeline   : timeline,
            expiresAt  : now.addingTimeInterval(60),
            stalePolicy: .retainMarked
        )
    }

    private func connect(
        _ state: inout PublicationState,
        scopes : [AssetState.Scope]
    ) throws -> PublicationConnection {
        try state.openConnection(
            identity              : scopes[0].identity,
            verifiedDigest        : scopes[0].verifiedDigest,
            manifestProtocol      : ProtocolVersion(major: 1, minimumMinor: 0),
            offer                 : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            ),
            authorizedPublications: scopes.map(\.publicationID)
        )
    }

    private func prepare(
        _ state     : PublicationState,
        connection  : PublicationConnection,
        publications: [Publication],
        sequence    : UInt64 = 1,
        ends        : [PublicationID] = []
    ) throws -> PublicationState.PreparedOutput {
        try state.prepareOutput(
            ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            generation: connection.generation,
            sequence  : sequence
        )
    }

    private func backing(_ coordinator: AssetDisposalCoordinator) async throws -> AssetRasterBacking {
        try await coordinator.create(
            pixels: Data([255, 0, 0, 255]),
            width : 1,
            height: 1,
            owner : owner
        )
    }

    @Test
    func opaqueImportRequiresExactScopeAndCurrentToken() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets      = AssetState()
        let original    = scope()
        let alias       = try assets.insert(
            backing: await backing(coordinator),
            scope  : original
        ).assetID
        _ = try content([alias])
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        let prepared     = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(original, ids: [alias])
            ]
        )
        for wrong in [
            scope(id: original.publicationID),
            scope(
                id       : original.publicationID,
                token    : original.connectionToken,
                publisher: "foreign"
            ),
            scope(
                id    : original.publicationID,
                token : original.connectionToken,
                digest: "foreign"
            ),
            scope(
                id     : original.publicationID,
                token  : original.connectionToken,
                feature: "foreign"
            ),
        ] {
            #expect(throws: AddonFailure.self) {
                try assets.prepareOutput(
                    prepared,
                    connectionToken: wrong.connectionToken
                ) { _ in wrong }
            }
        }

        let pins = try assets.prepareOutput(
            prepared,
            connectionToken: original.connectionToken
        ) { _ in original }
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )

        try assets.validatePrepared(pins)
        _ = try publications.commitPreparedOutput(prepared, at: now)
        assets.commitPrepared(pins)
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            )?.width == 1
        )
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 2,
                at                 : now
            ) == nil
        )
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : scope().publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )
    }

    @Test
    func rejectedBatchDoesNotPartiallyBindAndCrossPublicationIsDenied() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets      = AssetState()
        let first       = scope()
        let second      = scope()
        let alias       = try assets.insert(
            backing: await backing(coordinator),
            scope  : first
        ).assetID
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [first, second])
        let prepared     = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(first, ids: [alias]),
                publication(second, ids: [alias]),
            ]
        )
        let bytes = assets.retainedBytes
        #expect(throws: AddonFailure.self) {
            try assets.prepareOutput(prepared, connectionToken: first.connectionToken) { id in
                id == first.publicationID
                    ? first
                    : scope(id: second.publicationID, token: first.connectionToken)
            }
        }
        #expect(assets.retainedBytes == bytes)
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : first.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )
    }

    @Test
    func connectionExitKeepsPublicationButRejectsReconnectAliasAndStaleProposal() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets      = AssetState()
        let original    = scope()
        let alias       = try assets.insert(
            backing: await backing(coordinator),
            scope  : original
        ).assetID
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        let prepared     = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(original, ids: [alias])
            ]
        )
        let pins = try assets.prepareOutput(
            prepared,
            connectionToken: original.connectionToken
        ) { _ in original }
        try assets.validatePrepared(pins)
        _ = try publications.commitPreparedOutput(prepared, at: now)
        assets.commitPrepared(pins)
        #expect(throws: AddonFailure.self) { try assets.validatePrepared(pins) }

        assets.revokeImports(connectionToken: original.connectionToken)
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) != nil
        )

        let next = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(
                    original,
                    ids     : [alias],
                    revision: 2
                )
            ],
            sequence    : 2
        )
        let reconnected = scope(id: original.publicationID)
        #expect(throws: AddonFailure.self) {
            try assets.prepareOutput(
                next,
                connectionToken: reconnected.connectionToken
            ) { _ in reconnected }
        }
        #expect(throws: AddonFailure.self) {
            try assets.prepareOutput(
                next,
                connectionToken: original.connectionToken
            ) { _ in original }
        }
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now.addingTimeInterval(60)
            ) == nil
        )

        assets.reconcile(publications: publications, at: now.addingTimeInterval(60))
        #expect(assets.retainedBytes == 0)
    }

    @Test
    func futureTimelineImageSurvivesUntilPublicationAndLastConsumerRelease() async throws {
        let governor    = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets      = AssetState()
        let original    = scope()
        let alias       = try assets.insert(
            backing: await backing(coordinator),
            scope  : original
        ).assetID
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        let value        = try publication(
            original,
            ids     : [],
            timeline: [
                ScheduledEntry(date: now, content: content([])),
                ScheduledEntry(
                    date   : now.addingTimeInterval(30),
                    content: content([alias], privacy: .sensitive)
                ),
            ]
        )
        do {
            let prepared = try prepare(
                publications,
                connection  : connection,
                publications: [value]
            )
            let pins = try assets.prepareOutput(
                prepared,
                connectionToken: original.connectionToken
            ) { _ in original }
            try assets.validatePrepared(pins)
            _ = try publications.commitPreparedOutput(prepared, at: now)
            assets.commitPrepared(pins)
        }

        assets.revokeImports(connectionToken: original.connectionToken)
        var image: CGImage? = assets.image(
            assetID            : alias,
            publicationID      : original.publicationID,
            publicationRevision: 1,
            at                 : now
        )
        #expect(image?.width == 1)

        assets.removeOwner(owner)
        #expect(assets.retainedBytes(owner: owner) == 0)

        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 4)

        image = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
    }

    @Test
    func quotaRejectsBeforeCanonicalGrowthAndMutationInvalidatesPrepare() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        let raster      = try await backing(coordinator)
        let original    = scope()
        var denied      = AssetState(maximumRetainedBytes: 0)
        #expect(throws: AddonFailure.self) {
            try denied.insert(backing: raster, scope: original)
        }
        #expect(denied.retainedBytes == 0)

        var assets       = AssetState()
        let alias        = try assets.insert(backing: raster, scope: original).assetID
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        let output       = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(original, ids: [alias])
            ]
        )
        let pins = try assets.prepareOutput(
            output,
            connectionToken: original.connectionToken
        ) { _ in original }
        _ = try assets.insert(backing: raster, scope: original)
        #expect(throws: AddonFailure.self) { try assets.validatePrepared(pins) }
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )

        let bytes = assets.retainedBytes
        #expect(bytes == assets.retainedBytes(owner: owner))

        var limited = AssetState(maximumRetainedBytes: bytes)
        _ = try limited.insert(backing: raster, scope: original)
        _ = try limited.insert(backing: raster, scope: original)
        #expect(throws: AddonFailure.self) {
            try limited.insert(backing: raster, scope: original)
        }
        #expect(throws: AddonFailure.self) { try limited.preparationBytes(output) }
        #expect(limited.retainedBytes == bytes)
    }

    @Test
    func endRevokesImportsWhileUnpublishedAssignmentsSurviveReconciliation() async throws {
        let coordinator  = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets       = AssetState()
        let original     = scope()
        let notPublished = scope()
        let handle       = try assets.insert(backing: await backing(coordinator), scope: original)
        let pending      = try assets.insert(backing: await backing(coordinator), scope: notPublished)
        #expect(handle.owner == owner)
        #expect(handle.publicationID == original.publicationID)
        #expect(handle.rasterRevision == 1)
        #expect(handle.width == 1 && handle.height == 1 && handle.byteCount == 4)

        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original, notPublished])
        assets.reconcile(publications: publications, at: now)
        #expect(assets.retainedBytes == 8_192)

        do {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [
                    publication(original, ids: [handle.assetID])
                ]
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            #expect(proposal.retainedBytesAfter == 11_264)
            #expect(proposal.requiredGrowth == 3_072)
            #expect(proposal.estimatedBytes >= proposal.requiredGrowth)

            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        do {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [],
                sequence    : 2,
                ends        : [original.publicationID]
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        #expect(assets.retainedBytes == 4_096)
        #expect(
            assets.image(
                assetID            : handle.assetID,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )

        assets.reconcile(publications: publications, at: now)
        let output = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(notPublished, ids: [pending.assetID])
            ],
            sequence    : 3
        )
        let proposal = try assets.prepareOutput(
            output,
            connectionToken: notPublished.connectionToken
        ) { _ in notPublished }
        try assets.validatePrepared(proposal)
        _ = try publications.commitPreparedOutput(output, at: now)
        assets.commitPrepared(proposal)
        #expect(
            assets.image(
                assetID            : pending.assetID,
                publicationID      : notPublished.publicationID,
                publicationRevision: 1,
                at                 : now
            ) != nil
        )
    }

    @Test
    func replacementInvalidatesOldPublicationRevisionAndForeignProposalIsDenied() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets      = AssetState()
        let original    = scope()
        let alias       = try assets.insert(
            backing: await backing(coordinator),
            scope  : original
        ).assetID
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        for revision: UInt64 in [1, 2] {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [
                    publication(
                        original,
                        ids     : revision == 1 ? [alias] : [],
                        revision: revision
                    )
                ],
                sequence    : revision
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            let foreign = AssetState()
            #expect(throws: AddonFailure.self) { try foreign.validatePrepared(proposal) }

            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )
        #expect(
            assets.image(
                assetID            : alias,
                publicationID      : original.publicationID,
                publicationRevision: 2,
                at                 : now
            ) == nil
        )

        assets.revokeImports(connectionToken: original.connectionToken)
        #expect(assets.retainedBytes == 0)
    }

    @Test
    func assetlessOutputRequiresNoAssetMetadataAtFullQuota() throws {
        var assets       = AssetState(maximumRetainedBytes: 0)
        let original     = scope()
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        let output       = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(original, ids: [])
            ]
        )
        #expect(try assets.preparationBytes(output) == 0)

        let proposal = try assets.prepareOutput(
            output,
            connectionToken: original.connectionToken
        ) { _ in original }
        #expect(proposal.estimatedBytes == 0)
        #expect(proposal.retainedBytesAfter == 0)

        try assets.validatePrepared(proposal)
        _ = try publications.commitPreparedOutput(output, at: now)
        assets.commitPrepared(proposal)
        let ended = try prepare(
            publications,
            connection  : connection,
            publications: [],
            sequence    : 2,
            ends        : [original.publicationID]
        )
        #expect(try assets.preparationBytes(ended) == 0)

        let endedProposal = try assets.prepareOutput(
            ended,
            connectionToken: original.connectionToken
        ) { _ in original }
        try assets.validatePrepared(endedProposal)
        _ = try publications.commitPreparedOutput(ended, at: now)
        assets.commitPrepared(endedProposal)
        #expect(assets.retainedBytes == 0)
    }

    @Test
    func releaseImportRejectsForeignScopesAndRevokesUnpublishedAlias() async throws {
        let governor    = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets      = AssetState()
        let original    = scope()
        let handle      = try assets.insert(backing: await backing(coordinator), scope: original)
        for foreign in [
            scope(id: original.publicationID),
            scope(
                id       : original.publicationID,
                token    : original.connectionToken,
                publisher: "other.publisher"
            ),
            scope(
                id    : original.publicationID,
                token : original.connectionToken,
                digest: "other-digest"
            ),
            scope(
                id     : original.publicationID,
                token  : original.connectionToken,
                feature: "other-feature"
            ),
            scope(token: original.connectionToken),
        ] {
            #expect(throws: AddonFailure.self) {
                try assets.releaseImport(assetID: handle.assetID, scope: foreign)
            }
            #expect(assets.retainedBytes == 4_096)
        }
        #expect(throws: AddonFailure.self) {
            try assets.releaseImport(assetID: "asset-unknown", scope: original)
        }
        #expect(assets.retainedBytes == 4_096)

        try assets.releaseImport(assetID: handle.assetID, scope: original)
        #expect(assets.retainedBytes == 0)
        #expect(throws: AddonFailure.self) {
            try assets.releaseImport(assetID: handle.assetID, scope: original)
        }

        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        let output       = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(original, ids: [handle.assetID])
            ]
        )
        #expect(throws: AddonFailure.self) {
            try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
        }

        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
    }

    @Test
    func releasedImportKeepsPublishedPinUntilReplacementAndFinalImageRelease() async throws {
        let governor     = ResourceGovernor()
        let coordinator  = AssetDisposalCoordinator(governor: governor)
        var assets       = AssetState()
        let original     = scope()
        let handle       = try assets.insert(backing: await backing(coordinator), scope: original)
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        do {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [
                    publication(original, ids: [handle.assetID])
                ]
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        try assets.releaseImport(assetID: handle.assetID, scope: original)
        #expect(assets.retainedBytes == 3_072)

        var consumer: CGImage? = assets.image(
            assetID            : handle.assetID,
            publicationID      : original.publicationID,
            publicationRevision: 1,
            at                 : now
        )
        #expect(consumer?.width == 1)

        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 4)

        do {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [
                    publication(
                        original,
                        ids     : [],
                        revision: 2
                    )
                ],
                sequence    : 2
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        #expect(assets.retainedBytes == 0)
        #expect(
            assets.image(
                assetID            : handle.assetID,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )

        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 4)

        consumer = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
    }

    @Test(arguments: [false, true])
    func removalAtFullAssetMetadataQuotaNeedsNoGrowth(replaceWithAssetlessContent: Bool) async throws {
        let coordinator  = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets       = AssetState(maximumRetainedBytes: 7_168)
        let original     = scope()
        let handle       = try assets.insert(backing: await backing(coordinator), scope: original)
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection   = try connect(&publications, scopes: [original])
        do {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [
                    publication(original, ids: [handle.assetID])
                ]
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        #expect(assets.retainedBytes == 7_168)

        let output = try prepare(
            publications,
            connection  : connection,
            publications: replaceWithAssetlessContent
                ? [
                    publication(
                        original,
                        ids     : [],
                        revision: 2
                    )
                ] : [],
            sequence    : 2,
            ends        : replaceWithAssetlessContent ? [] : [original.publicationID]
        )
        #expect(try assets.preparationBytes(output) == 0)

        let proposal = try assets.prepareOutput(
            output,
            connectionToken: original.connectionToken
        ) { _ in original }
        #expect(proposal.estimatedBytes == 0)

        try assets.validatePrepared(proposal)
        _ = try publications.commitPreparedOutput(output, at: now)
        assets.commitPrepared(proposal)
        #expect(assets.retainedBytes == (replaceWithAssetlessContent ? 4_096 : 0))
        #expect(
            assets.image(
                assetID            : handle.assetID,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )
    }

    @Test
    func mixedBatchCannotFundNewPinsUsingProposedRemovalRefunds() async throws {
        let coordinator    = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets         = AssetState(maximumRetainedBytes: 11_264)
        let original       = scope()
        let other          = scope(token: original.connectionToken)
        let originalHandle = try assets.insert(backing: await backing(coordinator), scope: original)
        let otherHandle    = try assets.insert(backing: await backing(coordinator), scope: other)
        var publications   = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection     = try connect(&publications, scopes: [original, other])
        do {
            let output = try prepare(
                publications,
                connection  : connection,
                publications: [
                    publication(original, ids: [originalHandle.assetID])
                ]
            )
            let proposal = try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { _ in original }
            try assets.validatePrepared(proposal)
            _ = try publications.commitPreparedOutput(output, at: now)
            assets.commitPrepared(proposal)
        }

        #expect(assets.retainedBytes == 11_264)

        let output = try prepare(
            publications,
            connection  : connection,
            publications: [
                publication(
                    original,
                    ids     : [],
                    revision: 2
                ),
                publication(other, ids: [otherHandle.assetID]),
            ],
            sequence    : 2
        )
        #expect(throws: AddonFailure.self) { try assets.preparationBytes(output) }
        #expect(throws: AddonFailure.self) {
            try assets.prepareOutput(
                output,
                connectionToken: original.connectionToken
            ) { publicationID in
                publicationID == original.publicationID ? original : other
            }
        }
        #expect(assets.retainedBytes == 11_264)
        #expect(
            assets.image(
                assetID            : originalHandle.assetID,
                publicationID      : original.publicationID,
                publicationRevision: 1,
                at                 : now
            ) != nil
        )
        #expect(
            assets.image(
                assetID            : otherHandle.assetID,
                publicationID      : other.publicationID,
                publicationRevision: 1,
                at                 : now
            ) == nil
        )
    }
}
