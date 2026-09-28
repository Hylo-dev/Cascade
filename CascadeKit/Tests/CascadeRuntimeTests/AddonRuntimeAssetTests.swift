//
//  AddonRuntimeAssetTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonRuntimeAssetTests {
    @Test
    func importedImageIsPublicationPinnedAcrossProviderExitAndRequiresFreshReconnectAlias()
        async throws
    {
        let fixture = try await AssetRuntimeFixture.make()
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        #expect(handle.width == 1)
        #expect(handle.byteCount == 4)
        #expect(await fixture.image(handle.assetID) == nil)
        _ = try await fixture.publish(
            [fixture.publication(asset: handle.assetID)],
            sequence: 1
        )
        #expect(await fixture.image(handle.assetID)?.width == 1)
        #expect(
            await fixture.image(
                handle.assetID,
                revision: 2
            ) == nil
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(await fixture.image(handle.assetID)?.width == 1)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        let launch = try await fixture.runtime.requestLaunch(owner: fixture.owner)
        let reconnect = try await fixture.runtime.attach(
            launchID: launch,
            offer   : fixture.offer
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.publish(
                [
                    fixture.publication(
                        asset   : handle.assetID,
                        revision: 2
                    )
                ],
                sequence  : 1,
                connection: reconnect
            )
        }
        #expect(await fixture.image(handle.assetID)?.width == 1)
        let fresh = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : reconnect
        )
        #expect(fresh.assetID != handle.assetID)
        _ = try await fixture.publish(
            [
                fixture.publication(
                    asset   : fresh.assetID,
                    revision: 2
                )
            ],
            sequence  : 1,
            connection: reconnect
        )
        #expect(await fixture.image(handle.assetID) == nil)
        #expect(
            await fixture.image(
                fresh.assetID,
                revision: 2
            )?.width == 1
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(reconnect.incarnation)
    }

    @Test
    func crossPublicationBatchFailureDoesNotAdvanceSequenceOrPartiallyPublish() async throws {
        let fixture = try await AssetRuntimeFixture.make(count: 2)
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let before = await fixture.governor.usage(.retainedStateBytes)
        await #expect(throws: AddonFailure.self) {
            try await fixture.publish(
                [
                    fixture.publication(asset: handle.assetID),
                    fixture.publication(
                        asset: handle.assetID,
                        index: 1
                    )
                ],
                sequence: 1
            )
        }
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
        #expect(await fixture.governor.usage(.publications) == 0)
        #expect(await fixture.governor.usage(.retainedStateBytes) == before)
        _ = try await fixture.publish(
            [fixture.publication(asset: handle.assetID)],
            sequence: 1
        )
        #expect(await fixture.image(handle.assetID)?.width == 1)
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test
    func futureTimelineSurvivesExitAndExpiryRevokesLookupButNotBorrowedImageCharge() async throws {
        let fixture = try await AssetRuntimeFixture.make()
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let publication = try Publication(
            id      : fixture.ids[0],
            revision: 1,
            kind    : .widget,
            content : nil,
            timeline: [
                ScheduledEntry(
                    date   : fixture.wall,
                    content: fixture.content(nil)
                ),
                ScheduledEntry(
                    date   : fixture.wall.addingTimeInterval(30),
                    content: fixture.content(handle.assetID)
                )
            ],
            expiresAt  : fixture.wall.addingTimeInterval(60),
            stalePolicy: .retainMarked
        )
        _ = try await fixture.publish(
            [publication],
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        var borrowed = await fixture.image(handle.assetID)
        #expect(borrowed?.width == 1)
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(61),
                monotonic: .seconds(61)
            )
        )
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(await fixture.image(handle.assetID) == nil)
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(borrowed?.height == 1)
        borrowed = nil
        for _ in 0..<1000 {
            if await fixture.governor.usage(.assetBytes) == 0 { break }
            await Task.yield()
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        await fixture.runtime.stop()
    }

    @Test
    func disableDuringImportMetadataAdmissionRejectsBeforeDecodeAndRefundsPool() async throws {
        let fixture = try await AssetRuntimeFixture.make()
        await fixture.access.armResize()
        let task = Task {
            try await fixture.runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        await fixture.access.waitForArrival()
        await fixture.runtime.disable(owner: fixture.owner)
        await fixture.access.releaseGate()
        await #expect(throws: AddonFailure.self) { try await task.value }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        await fixture.runtime.stop()
    }
    @Test
    func endAndDisableRevokePublishedAndUnpublishedAliases() async throws {
        for shouldDisable in [false, true] {
            let fixture = try await AssetRuntimeFixture.make()
            let handle = try await fixture.runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
            _ = try await fixture.publish(
                [fixture.publication(asset: handle.assetID)],
                sequence: 1
            )
            #expect(await fixture.image(handle.assetID)?.width == 1)
            if shouldDisable {
                await fixture.runtime.disable(owner: fixture.owner)
            } else {
                _ = try await fixture.publish(
                    [],
                    sequence: 2,
                    ends    : [fixture.ids[0]]
                )
            }
            #expect(await fixture.image(handle.assetID) == nil)
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.importAsset(
                    encoded      : runtimeAssetPNG(),
                    publicationID: fixture.ids[0],
                    connection   : fixture.connection
                )
            }
            for _ in 0..<1000 {
                if await fixture.governor.usage(.assetBytes) == 0 { break }
                await Task.yield()
            }
            #expect(await fixture.governor.usage(.assetBytes) == 0)
            await fixture.runtime.stop()
            await fixture.runtime.observeExit(fixture.connection.incarnation)
        }
    }

    @Test
    func publicationAdmissionCancellationOrDisableCannotCommitAssetPins() async throws {
        for shouldDisable in [false, true] {
            let fixture = try await AssetRuntimeFixture.make()
            let handle = try await fixture.runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
            await fixture.access.armResize()
            let task = Task {
                try await fixture.publish(
                    [fixture.publication(asset: handle.assetID)],
                    sequence: 1
                )
            }
            await fixture.access.waitForArrival()
            if shouldDisable {
                await fixture.runtime.disable(owner: fixture.owner)
            } else {
                task.cancel()
            }
            await fixture.access.releaseGate()
            await #expect(throws: (any Error).self) { try await task.value }
            #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
            #expect(await fixture.image(handle.assetID) == nil)
            #expect(await fixture.governor.usage(.publications) == 0)
            if !shouldDisable {
                _ = try await fixture.publish(
                    [fixture.publication(asset: handle.assetID)],
                    sequence: 1
                )
                #expect(await fixture.image(handle.assetID)?.width == 1)
            }
            await fixture.runtime.stop()
            await fixture.runtime.observeExit(fixture.connection.incarnation)
        }
    }

    @Test
    func failedDecodeAndAssetQuotaAdmissionDoNotRetainRuntimeMetadata() async throws {
        let fixture = try await AssetRuntimeFixture.make()
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.importAsset(
                encoded      : Data([1, 2, 3]),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        let usedMemory = await fixture.governor.usage(
            .admittedMemoryBytes,
            owner: fixture.owner
        )
        let held = try await fixture.governor.admit(
            .temporaryMemory(bytes: 128 * 1_024 * 1_024 - usedMemory - 1_024 * 1_024),
            owner: fixture.owner
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        try await fixture.governor.release(
            held.id,
            owner: fixture.owner
        )
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        _ = try await fixture.publish(
            [fixture.publication(asset: handle.assetID)],
            sequence: 1
        )
        #expect(await fixture.image(handle.assetID)?.width == 1)
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test
    func metadataQuotaDeniesImportAndPublicationWithoutPartialState() async throws {
        let fixture = try await AssetRuntimeFixture.make()
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let fillerOwner = try #require(AddonID(rawValue: "com.example.asset-quota-filler"))
        let used = await fixture.governor.usage(.retainedStateBytes)
        let filler = try await fixture.governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - used - 1_024),
            owner: fillerOwner
        )
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        await #expect(throws: AddonFailure.self) {
            try await fixture.publish(
                [fixture.publication(asset: handle.assetID)],
                sequence: 1
            )
        }
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
        #expect(await fixture.governor.usage(.publications) == 0)
        try await fixture.governor.release(
            filler.id,
            owner: fillerOwner
        )
        _ = try await fixture.publish(
            [fixture.publication(asset: handle.assetID)],
            sequence: 1
        )
        #expect(await fixture.image(handle.assetID)?.width == 1)
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test
    func directImportAndReleaseReconcilePoolMetadata() async throws {
        let fixture = try await AssetRuntimeFixture.make()
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let imported = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        #expect((imported ?? 0) > (before ?? 0))
        try await fixture.runtime.releaseAsset(
            assetID      : handle.assetID,
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test
    func successfulImportDrainsServiceCompletionWithoutRequiringAnotherEvent() async throws {
        let consumer = try installedFixture(
            "consumer",
            publisher: "shared.publisher"
        )
        let provider = try installedFixture(
            "focus",
            publisher: "shared.publisher"
        )
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let now = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [consumer, provider],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [consumer.manifest.id: [], provider.manifest.id: []],
                explicitBindings: [
                    ServiceBinding(
                        requirementID   : "com.example.focus.sessions",
                        consumer        : consumer.manifest.id,
                        provider        : provider.manifest.id,
                        providerIdentity: provider.verifiedIdentity,
                        contractVersion : SemanticVersion(
                            1,
                            0,
                            0
                        ),
                        digest   : provider.digest,
                        featureID: "summary"
                    )
                ]
            ),
            governor              : governor,
            resourceAccess        : access,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : FixedRuntimeClock(instant: now)
        )
        let id = try await runtime.assignPublication(
            owner     : provider.manifest.id,
            featureID : "localTimer",
            instanceID: UUID()
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let launch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let consumerConnection = try await runtime.attach(
            launchID: launch,
            offer   : offer
        )
        let permission = try await runtime.authorizeService(
            connection   : consumerConnection,
            requirementID: "com.example.focus.sessions",
            scope        : ServiceScope(
                featureID: "summary",
                operation: "read"
            ),
            partition            : "account",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permission,
                lifetime    : .seconds(30)
            )
        }
        let start = try #require(adapter.lastStart(owner: provider.manifest.id))
        let providerConnection = try await runtime.attach(
            launchID: start.launchID,
            offer   : offer
        )
        let acquisition = try await runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permission,
            lifetime    : .seconds(30)
        )
        if await governor.usage(
            .jobs,
            owner: provider.manifest.id
        ) == 1 {
            #expect(
                try await runtime.receiveSourceStartupCompletion(
                    acquisition.sourceID,
                    connection: providerConnection
                )
            )
        }
        let invocation = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data([1]),
            deadline     : now.wall.addingTimeInterval(20)
        )
        let work = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: invocation
        )
        #expect(try await runtime.pumpServiceInvocation(work.id))
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : invocation.contractID,
            operation    : "read",
            payload      : Data([9])
        )
        await access.armResize()
        let importing = Task {
            try await runtime.importAsset(
                encoded      : runtimeAssetPNG(),
                publicationID: id,
                connection   : providerConnection
            )
        }
        await access.waitForArrival()
        #expect(
            try await runtime.receiveServiceCompletion(
                work.id,
                connection: providerConnection,
                response  : response
            ) == .pending
        )
        await access.releaseGate()
        let handle = try await importing.value
        #expect(handle.width == 1)
        let outcome = try? await runtime.serviceOutcome(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            requestID : invocation.requestID
        )
        #expect(outcome == .completed(response))
        #expect(
            await governor.usage(
                .jobs,
                owner: provider.manifest.id
            ) == 0
        )
        await runtime.stop()
        await runtime.observeExit(providerConnection.incarnation)
        await runtime.observeExit(consumerConnection.incarnation)
    }

    @Test
    func releaseImportPreservesPublishedImageButCannotAuthorizeLaterRevision() async throws {
        let fixture = try await AssetRuntimeFixture.make(count: 2)
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        _ = try await fixture.publish(
            [fixture.publication(asset: handle.assetID)],
            sequence: 1
        )
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.releaseAsset(
                assetID      : handle.assetID,
                publicationID: fixture.ids[1],
                connection   : fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        try await fixture.runtime.releaseAsset(
            assetID      : handle.assetID,
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let after = try #require(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        )
        #expect(after < (before ?? 0))
        #expect(await fixture.image(handle.assetID)?.width == 1)
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.releaseAsset(
                assetID      : handle.assetID,
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == after
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.publish(
                [
                    fixture.publication(
                        asset   : handle.assetID,
                        revision: 2
                    )
                ],
                sequence: 2
            )
        }
        #expect(await fixture.image(handle.assetID)?.width == 1)
        _ = try await fixture.publish(
            [
                fixture.publication(
                    asset   : nil,
                    revision: 2
                )
            ],
            sequence: 2
        )
        #expect(await fixture.image(handle.assetID) == nil)
        for _ in 0..<1000 {
            if await fixture.governor.usage(.assetBytes) == 0 { break }
            await Task.yield()
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test(arguments: [false, true])
    func removingAssetPinsNeedsNoStateGrowthAfterScratchAdmission(replaceWithAssetlessContent: Bool)
        async throws
    {
        let fixture = try await AssetRuntimeFixture.make()
        let handle = try await fixture.runtime.importAsset(
            encoded      : runtimeAssetPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        _ = try await fixture.publish(
            [fixture.publication(asset: handle.assetID)],
            sequence: 1
        )
        await fixture.access.armTemporaryMemory()
        let ending = Task {
            try await fixture.publish(
                replaceWithAssetlessContent
                    ? [
                        fixture.publication(
                            asset   : nil,
                            revision: 2
                        )
                    ] : [],
                sequence: 2,
                ends    : replaceWithAssetlessContent ? [] : [fixture.ids[0]]
            )
        }
        await fixture.access.waitForArrival()
        let used = await fixture.governor.usage(.retainedStateBytes)
        let fillerOwner = try #require(AddonID(rawValue: "com.example.asset-end-filler"))
        let filler = try await fixture.governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - used - 1_024),
            owner: fillerOwner
        )
        #expect(await fixture.governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)
        await fixture.access.releaseGate()
        _ = try await ending.value
        let publications = await fixture.runtime.snapshot(at: fixture.wall).publications
        #expect(publications.count == (replaceWithAssetlessContent ? 1 : 0))
        #expect(await fixture.image(handle.assetID) == nil)
        #expect(
            await fixture.governor.usage(.publications) == (replaceWithAssetlessContent ? 1 : 0)
        )
        try await fixture.governor.release(
            filler.id,
            owner: fillerOwner
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

}

private struct AssetRuntimeFixture: Sendable {
    let runtime   : AddonRuntime
    let governor  : ResourceGovernor
    let access    : GatedRuntimeResourceAccess
    let adapter   : RecordingRuntimeAdapter
    let clock     : MutableRuntimeClock
    let owner     : AddonID
    let ids       : [PublicationID]
    let connection: RuntimeConnection
    let wall      : Date
    var offer     : ProtocolOffer {
        get throws {
            try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        }
    }
    static func make(count: Int = 1) async throws -> Self {
        let base = try ActionFixture()
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(
            instant: RuntimeInstant(
                wall     : base.wall,
                monotonic: .zero
            )
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [base.context().installed],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [base.owner: []],
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : access,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock
        )
        var ids: [PublicationID] = []
        for _ in 0..<count {
            ids.append(
                try await runtime.assignPublication(
                    owner     : base.owner,
                    featureID : "controls",
                    instanceID: UUID()
                )
            )
        }
        let launch = try await runtime.requestLaunch(owner: base.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        return Self(
            runtime   : runtime,
            governor  : governor,
            access    : access,
            adapter   : adapter,
            clock     : clock,
            owner     : base.owner,
            ids       : ids,
            connection: connection,
            wall      : base.wall
        )
    }
    func content(_ asset: String?) throws -> PresentationSet {
        try PresentationSet(
            widget: ContentDocument(
                root              : .text("Image"),
                privacy           : .publicContent,
                accessibilityLabel: "Image",
                assetIDs          : asset.map { [$0] } ?? []
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }
    func publication(
        asset   : String?,
        index   : Int = 0,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : ids[index],
            revision   : revision,
            kind       : .widget,
            content    : content(asset),
            timeline   : nil,
            expiresAt  : wall.addingTimeInterval(60),
            stalePolicy: .remove
        )
    }
    func publish(
        _ publications: [Publication],
        sequence      : UInt64,
        connection    : RuntimeConnection? = nil,
        ends          : [PublicationID] = []
    ) async throws -> PublicationAdmission {
        try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection ?? self.connection,
            sequence  : sequence
        )
    }
    func image(
        _ asset : String,
        revision: UInt64 = 1
    ) async -> CGImage? {
        await runtime.assetImage(
            assetID            : asset,
            publicationID      : ids[0],
            publicationRevision: revision
        )
    }
}

/// runtimeAssetPNG encodes a real one-pixel image for the production ImageIO decoder.
private func runtimeAssetPNG() throws -> Data {
    let data = NSMutableData()
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try #require(CGDataProvider(data: Data([255, 0, 0, 255]) as CFData))
    let image = try #require(
        CGImage(
            width            : 1,
            height           : 1,
            bitsPerComponent : 8,
            bitsPerPixel     : 32,
            bytesPerRow      : 4,
            space            : colorSpace,
            bitmapInfo       : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider         : provider,
            decode           : nil,
            shouldInterpolate: false,
            intent           : .defaultIntent
        )
    )
    let destination = try #require(
        CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        )
    )
    CGImageDestinationAddImage(
        destination,
        image,
        nil
    )
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
