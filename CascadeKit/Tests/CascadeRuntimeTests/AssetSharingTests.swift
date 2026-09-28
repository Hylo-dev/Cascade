//
//  AssetSharingTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AssetSharingTests {
    private let identity: VerifiedAddonIdentity
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    init() throws {
        identity = VerifiedAddonIdentity(
            publisher: "test.publisher",
            addonID  : try #require(AddonID(rawValue: "com.example.shared-assets"))
        )
    }

    private func scope(
        token    : UUID,
        partition: AssetPrivacyPartition = .addonOwned,
        feature  : String = "widget",
        identity : VerifiedAddonIdentity? = nil,
        digest   : String = "test-digest",
        id       : PublicationID? = nil
    ) -> AssetState.Scope {
        let assignedIdentity = identity ?? self.identity
        return AssetState.Scope(
            identity        : assignedIdentity,
            verifiedDigest  : digest,
            featureID       : feature,
            publicationID   : id ?? PublicationID(
                addonID   : assignedIdentity.addonID,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            connectionToken : token,
            privacyPartition: partition
        )
    }

    private func importRaster(
        into assets: inout AssetState,
        scope      : AssetState.Scope,
        coordinator: AssetDisposalCoordinator
    ) async throws -> AssetState.AssetHandle {
        try assets.insert(
            backing: await coordinator.create(
                pixels     : Data([255, 0, 0, 255]),
                width      : 1,
                height     : 1,
                owner      : identity.addonID
            ),
            scope: scope
        )
    }

    private func publication(
        scope   : AssetState.Scope,
        alias   : String,
        duration: TimeInterval = 60,
        privacy : ContentDocument.Privacy = .publicContent
    ) throws -> Publication {
        try Publication(
            id         : scope.publicationID,
            revision   : 1,
            kind       : .widget,
            content    : PresentationSet(
                widget         : ContentDocument(
                    root              : .text("Ready"),
                    privacy           : privacy,
                    accessibilityLabel: "Ready",
                    assetIDs          : [alias]
                ),
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : now.addingTimeInterval(duration),
            stalePolicy: .retainMarked
        )
    }

    private func connect(
        publications: inout PublicationState,
        scopes      : [AssetState.Scope]
    ) throws -> PublicationConnection {
        try publications.openConnection(
            identity              : identity,
            verifiedDigest        : "test-digest",
            manifestProtocol      : ProtocolVersion(
                major       : 1,
                minimumMinor: 0
            ),
            offer                 : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            ),
            authorizedPublications: scopes.map(\.publicationID)
        )
    }

    private func commit(
        assets      : inout AssetState,
        publications: inout PublicationState,
        connection  : PublicationConnection,
        scopes      : [AssetState.Scope],
        values      : [Publication],
        sequence    : UInt64 = 1,
        endedIDs    : [PublicationID] = []
    ) throws {
        let prepared = try publications.prepareOutput(
            ProviderOutput(
                schemaVersion: 1,
                publications : values,
                operations   : endedIDs.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            generation: connection.generation,
            sequence  : sequence
        )
        let firstScope = try #require(scopes.first)
        let proposal = try assets.prepareOutput(
            prepared,
            connectionToken: firstScope.connectionToken
        ) { publicationID in
            try #require(scopes.first { $0.publicationID == publicationID })
        }
        try assets.validatePrepared(proposal)
        _ = try publications.commitPreparedOutput(
            prepared,
            at: now
        )
        assets.commitPrepared(proposal)
    }

    @Test
    func explicitSharingAcrossFeaturesCreatesDistinctAliasesWithOneRaster() async throws {
        let governor    = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets      = AssetState()
        let token       = UUID()
        let source      = scope(token: token)
        let target = scope(
            token  : token,
            feature: "activity"
        )
        let original = try await importRaster(
            into       : &assets,
            scope      : source,
            coordinator: coordinator
        )
        #expect(try assets.sharingAdmissionBytes(
            assetID: original.assetID,
            source : source,
            target : target
        ) == 4_096)
        let shared = try assets.share(
            assetID: original.assetID,
            source : source,
            target : target
        )
        #expect(shared.assetID != original.assetID)
        #expect(shared.publicationID == target.publicationID)
        #expect(shared.owner == original.owner)
        #expect(shared.rasterRevision == 1)
        #expect(shared.width == 1 && shared.height == 1 && shared.byteCount == 4)
        #expect(assets.retainedBytes == 8_192)
        #expect(await governor.usage(.assetBytes) == 4)
        #expect(coordinator.status().slots == 1)
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection = try connect(
            publications: &publications,
            scopes      : [source, target]
        )
        try commit(
            assets      : &assets,
            publications: &publications,
            connection  : connection,
            scopes      : [source, target],
            values      : [
                publication(
                    scope  : source,
                    alias  : original.assetID,
                    privacy: .sensitive
                ),
                publication(
                    scope: target,
                    alias: shared.assetID
                )
            ]
        )
        let sourceImage = try #require(assets.image(
            assetID            : original.assetID,
            publicationID      : source.publicationID,
            publicationRevision: 1,
            at                 : now
        ))
        let targetImage = try #require(assets.image(
            assetID            : shared.assetID,
            publicationID      : target.publicationID,
            publicationRevision: 1,
            at                 : now
        ))
        #expect(sourceImage === targetImage)
        try assets.releaseImport(
            assetID: original.assetID,
            scope  : source
        )
        #expect(try assets.sharingAdmissionBytes(
            assetID: shared.assetID,
            source : target,
            target : source
        ) == 4_096)
        #expect(assets.image(
            assetID            : shared.assetID,
            publicationID      : target.publicationID,
            publicationRevision: 1,
            at                 : now
        ) === targetImage)
        #expect(assets.image(
            assetID            : original.assetID,
            publicationID      : target.publicationID,
            publicationRevision: 1,
            at                 : now
        ) == nil)
        #expect(await governor.usage(.assetBytes) == 4)
    }

    @Test
    func incompatibleTargetsAndSpoofedSourceScopesFailBeforeMetadataGrowth() async throws {
        let governor    = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets      = AssetState()
        let token       = UUID()
        let source      = scope(token: token)
        let original = try await importRaster(
            into       : &assets,
            scope      : source,
            coordinator: coordinator
        )
        let foreignOwner = try #require(AddonID(rawValue: "com.example.other"))
        let incompatible = [
            scope(token: UUID()),
            scope(
                token    : token,
                partition: .isolated(UUID())
            ),
            scope(
                token   : token,
                identity: VerifiedAddonIdentity(
                    publisher: "other.publisher",
                    addonID  : identity.addonID
                )
            ),
            scope(
                token   : token,
                identity: VerifiedAddonIdentity(
                    publisher: identity.publisher,
                    addonID  : foreignOwner
                )
            ),
            scope(
                token : token,
                digest: "different-digest"
            ),
            scope(
                token  : token,
                feature: String(
                    repeating: "x",
                    count    : 129
                )
            ),
            scope(
                token: token,
                id   : PublicationID(
                    addonID   : foreignOwner,
                    instanceID: UUID(),
                    sessionID : UUID()
                )
            )
        ]
        for target in incompatible {
            #expect(throws: AddonFailure.self) {
                try assets.sharingAdmissionBytes(
                    assetID: original.assetID,
                    source : source,
                    target : target
                )
            }
            #expect(throws: AddonFailure.self) {
                try assets.share(
                    assetID: original.assetID,
                    source : source,
                    target : target
                )
            }
        }
        let target = scope(token: token)
        let spoofedSources = incompatible + [
            target,
            scope(
                token  : token,
                feature: "other-feature",
                id     : source.publicationID
            )
        ]
        for spoofed in spoofedSources {
            #expect(throws: AddonFailure.self) {
                try assets.share(
                    assetID: original.assetID,
                    source : spoofed,
                    target : target
                )
            }
        }
        #expect(assets.retainedBytes == 4_096)
        #expect(await governor.usage(.assetBytes) == 4)
        #expect(try assets.sharingAdmissionBytes(
            assetID: original.assetID,
            source : source,
            target : target
        ) == 4_096)
    }

    @Test
    func isolatedPartitionsShareOnlyWithinTheSameHostPartition() async throws {
        let coordinator = AssetDisposalCoordinator(governor: ResourceGovernor())
        var assets      = AssetState()
        let token       = UUID()
        let partition   = AssetPrivacyPartition.isolated(UUID())
        let source = scope(
            token    : token,
            partition: partition
        )
        let original = try await importRaster(
            into       : &assets,
            scope      : source,
            coordinator: coordinator
        )
        for target in [
            scope(token: token),
            scope(
                token    : token,
                partition: .isolated(UUID())
            )
        ] {
            #expect(throws: AddonFailure.self) {
                try assets.share(
                    assetID: original.assetID,
                    source : source,
                    target : target
                )
            }
        }
        let target = scope(
            token    : token,
            partition: partition,
            feature  : "another-feature"
        )
        let shared = try assets.share(
            assetID: original.assetID,
            source : source,
            target : target
        )
        #expect(shared.assetID != original.assetID)
        #expect(assets.retainedBytes == 8_192)
    }

    @Test
    func shareCapacityAndReleasedSourceFailWithoutCopyingOrRevivingRaster() async throws {
        let governor    = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets      = AssetState(maximumRetainedBytes: 8_191)
        let token       = UUID()
        let source      = scope(token: token)
        let target      = scope(token: token)
        let original = try await importRaster(
            into       : &assets,
            scope      : source,
            coordinator: coordinator
        )
        #expect(throws: AddonFailure.self) {
            try assets.sharingAdmissionBytes(
                assetID: original.assetID,
                source : source,
                target : target
            )
        }
        #expect(throws: AddonFailure.self) {
            try assets.share(
                assetID: original.assetID,
                source : source,
                target : target
            )
        }
        #expect(assets.retainedBytes == 4_096)
        #expect(coordinator.status().slots == 1)
        try assets.releaseImport(
            assetID: original.assetID,
            scope  : source
        )
        #expect(throws: AddonFailure.self) {
            try assets.share(
                assetID: original.assetID,
                source : source,
                target : target
            )
        }
        #expect(assets.retainedBytes == 0)
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
    }

    @Test(arguments: [false, true])
    func endingOrExpiringSourcePreservesTargetPinsAndLastConsumerLifetime(expireSource: Bool) async throws {
        let governor    = ResourceGovernor()
        let coordinator = AssetDisposalCoordinator(governor: governor)
        var assets      = AssetState()
        let token       = UUID()
        let source      = scope(token: token)
        let target      = scope(token: token)
        let original = try await importRaster(
            into       : &assets,
            scope      : source,
            coordinator: coordinator
        )
        let shared = try assets.share(
            assetID: original.assetID,
            source : source,
            target : target
        )
        var publications = PublicationState(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let connection = try connect(
            publications: &publications,
            scopes      : [source, target]
        )
        try commit(
            assets      : &assets,
            publications: &publications,
            connection  : connection,
            scopes      : [source, target],
            values      : [
                publication(
                    scope   : source,
                    alias   : original.assetID,
                    duration: 10
                ),
                publication(
                    scope: target,
                    alias: shared.assetID
                )
            ]
        )
        if expireSource {
            assets.reconcile(
                publications: publications,
                at          : now.addingTimeInterval(10)
            )
        } else {
            try commit(
                assets      : &assets,
                publications: &publications,
                connection  : connection,
                scopes      : [source, target],
                values      : [],
                sequence    : 2,
                endedIDs    : [source.publicationID]
            )
        }
        #expect(throws: AddonFailure.self) {
            try assets.share(
                assetID: original.assetID,
                source : source,
                target : target
            )
        }
        var consumer: CGImage? = assets.image(
            assetID            : shared.assetID,
            publicationID      : target.publicationID,
            publicationRevision: 1,
            at                 : now.addingTimeInterval(10)
        )
        #expect(consumer?.width == 1)
        #expect(assets.retainedBytes == 7_168)
        assets.revokeImports(connectionToken: token)
        #expect(assets.retainedBytes == 3_072)
        #expect(throws: AddonFailure.self) {
            try assets.share(
                assetID: shared.assetID,
                source : target,
                target : source
            )
        }
        #expect(assets.image(
            assetID            : shared.assetID,
            publicationID      : target.publicationID,
            publicationRevision: 1,
            at                 : now.addingTimeInterval(10)
        ) != nil)
        assets.reconcile(
            publications: publications,
            at          : now.addingTimeInterval(60)
        )
        #expect(assets.retainedBytes == 0)
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 4)
        consumer = nil
        try await coordinator.flushDisposed()
        #expect(await governor.usage(.assetBytes) == 0)
    }
}
