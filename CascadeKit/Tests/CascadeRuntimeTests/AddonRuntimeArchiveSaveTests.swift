//
//  AddonRuntimeArchiveSaveTests.swift
//  Cascade
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonRuntimeArchiveSaveTests {
    @Test func savesRevisionZeroAndCompleteTimelineThenIncrementsArchiveRevision() async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        let first       = try fixture.content(text: "First")
        let future      = try fixture.content(text: "Future")
        let publication = try Publication(
            id      : fixture.ids[0],
            revision: 0,
            kind    : .widget,
            content : nil,
            timeline: [
                ScheduledEntry(
                    date   : fixture.wall,
                    content: first
                ),
                ScheduledEntry(
                    date   : fixture.wall.addingTimeInterval(20),
                    content: future
                ),
            ],
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        try await fixture.publish(
            [publication],
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        let saved = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(saved.revision == 1)
        #expect(
            try await fixture.matches { envelope in
                guard envelope.records.count == 1, let record = envelope.records.first,
                    let json = record.publication
                else { return false }
                let decoded = try RuntimeArchivePublicationCodec.decode(json)
                return decoded == publication && record.revision == 0
                    && record.sessionDeadline >= publication.expiresAt && envelope.blobs.isEmpty
            }
        )
        let second = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(second.revision == 2)
        await fixture.runtime.stop()
    }

    @Test func savesSharedRasterOnceAcrossFeaturesAfterImportAuthorityEnds() async throws {
        let fixture = try await ArchiveSaveFixture.make(partitions: [.addonOwned, .addonOwned])
        defer { fixture.removeFiles() }
        let first = try await fixture.runtime.importAsset(
            encoded      : archiveSavePNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let second = try await fixture.runtime.shareAsset(
            assetID   : first.assetID,
            from      : fixture.ids[0],
            to        : fixture.ids[1],
            connection: fixture.connection
        )
        try await fixture.publish(
            [
                fixture.publication(
                    index: 0,
                    asset: first.assetID
                ),
                fixture.publication(
                    index: 1,
                    asset: second.assetID
                ),
            ],
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(
            try await fixture.matches { envelope in
                envelope.records.count == 2 && envelope.blobs.count == 1
                    && envelope.records.allSatisfy { $0.aliases.count == 1 }
                    && Set(envelope.records.map(\.feature)).count == 2
                    && envelope.records[0].aliases[0].blob == envelope.records[1].aliases[0].blob
                    && envelope.blobs[0].pixels == Data([255, 0, 0, 255])
            }
        )
        await fixture.runtime.stop()
    }
    @Test func preservesOriginalActivityAnchorTerminalHistoryAndOmitsNotices() async throws {
        let fixture = try await ArchiveSaveFixture.make(
            partitions: Array(
                repeating: .addonOwned,
                count    : 4
            )
        )
        defer { fixture.removeFiles() }
        let document = try ContentDocument(
            root              : .text("Activity"),
            privacy           : .publicContent,
            accessibilityLabel: "Activity"
        )
        let activityContent = try PresentationSet(
            widget         : nil,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : document
        )
        let noticeContent = try PresentationSet(
            widget         : nil,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : nil
        )
        let activity = try Publication(
            id         : fixture.ids[0],
            revision   : 3,
            kind       : .activity,
            content    : activityContent,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        let elapsed = try Publication(
            id         : fixture.ids[2],
            revision   : 8,
            kind       : .widget,
            content    : fixture.content(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(10),
            stalePolicy: .remove
        )
        let notice = try Publication(
            id         : fixture.ids[3],
            revision   : 1,
            kind       : .notice,
            content    : noticeContent,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(10),
            stalePolicy: .remove
        )
        try await fixture.publish(
            [activity, fixture.publication(index: 1), elapsed, notice],
            sequence: 1
        )
        try await fixture.publish(
            [],
            sequence: 2,
            ends    : [fixture.ids[1]]
        )
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(20),
                monotonic: .seconds(20)
            )
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(
            try await fixture.matches { envelope in
                guard envelope.records.count == 3,
                    let active = envelope.records.first(where: { $0.kind == .activity })
                else { return false }
                return active.sessionDeadline == fixture.wall.addingTimeInterval(8 * 3600)
                    && active.revision == 3 && active.publication != nil
                    && envelope.records.filter { $0.publication == nil }.count == 2
                    && envelope.records.contains { $0.revision == 8 && $0.publication == nil }
                    && envelope.records.allSatisfy { $0.kind != .notice }
            }
        )
        await fixture.runtime.stop()
    }

    @Test func equalPixelsInDifferentHostPartitionsRemainSeparateBlobs() async throws {
        let isolated = UUID()
        let fixture  = try await ArchiveSaveFixture.make(partitions: [.addonOwned, .isolated(isolated)])
        defer { fixture.removeFiles() }
        var publications: [Publication] = []
        for index in 0..<2 {
            let handle = try await fixture.runtime.importAsset(
                encoded      : archiveSavePNG(),
                publicationID: fixture.ids[index],
                connection   : fixture.connection
            )
            publications.append(
                try fixture.publication(
                    index: index,
                    asset: handle.assetID
                )
            )
        }
        try await fixture.publish(
            publications,
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(
            try await fixture.matches { envelope in
                envelope.blobs.count == 2 && envelope.blobs[0].pixels == envelope.blobs[1].pixels
                    && Set(envelope.blobs.map(\.partition)).count == 2
                    && envelope.blobs.contains { $0.partition == RuntimeArchiveEnvelope.uuidBytes(isolated) }
            }
        )
        await fixture.runtime.stop()
    }

    @Test(arguments: ["owner", "publisher", "governor"])
    func rejectsForeignBackendBeforeAdmission(_ mismatch: String) async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        let root = fixture.root.appendingPathComponent("foreign")
        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let identity = try VerifiedAddonIdentity(
            publisher: mismatch == "publisher"
                ? "other.publisher" : fixture.installed.verifiedIdentity.publisher,
            addonID: mismatch == "owner" ? #require(AddonID(rawValue: "com.example.other")) : fixture.owner
        )
        let governor = mismatch == "governor" ? ResourceGovernor() : fixture.governor
        let foreign  = try await SwiftDataArchive.make(
            identity: identity,
            root    : root,
            governor: governor
        )
        let before = await fixture.governor.usage(.admittedMemoryBytes)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : foreign
            )
        }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == before)
        #expect(await foreign.status().state == .unavailable)
        await fixture.stop()
    }

    @Test func exhaustedGenerationRevisionPreservesExistingArchive() async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        _ = try await fixture.archive.save(
            SwiftDataArchiveGeneration(
                schemaVersion : 1,
                revision      : UInt64.max,
                verifiedDigest: fixture.installed.digest,
                payload       : Data([1])
            ),
            replacing: nil
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        #expect(try await fixture.archive.withGeneration { $0?.revision == UInt64.max })
        await fixture.stop()
    }

    @Test(arguments: ["state", "memory"])
    func deniedAdmissionPreservesPriorArchiveAndRefundsTemporaryScopes(_ dimension: String) async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let beforeState  = await fixture.governor.usage(.retainedStateBytes)
        let filler: ResourceReservation
        if dimension == "state" {
            filler = try await fixture.governor.admit(
                .state(bytes: 8 * 1_024 * 1_024 - beforeState - 1_024),
                owner: fixture.owner
            )
        } else {
            filler = try await fixture.governor.admit(
                .temporaryMemory(bytes: 128 * 1_024 * 1_024 - beforeMemory - 1_024),
                owner: fixture.owner
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        try await fixture.governor.release(
            filler.id,
            owner: fixture.owner
        )
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        #expect(await fixture.governor.usage(.retainedStateBytes) == beforeState)
        #expect(try await fixture.archive.withGeneration { $0?.revision == 1 })
        await fixture.runtime.stop()
    }

    @Test(arguments: ["cancel", "disable"])
    func lifecycleChangeBeforeCapturePreservesPriorGeneration(_ change: String) async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        let before = await fixture.governor.usage(.admittedMemoryBytes)
        await observer.arm(after: 1)
        let saving = Task {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await observer.waitForArrival()
        if change == "cancel" { saving.cancel() } else { await fixture.runtime.disable(owner: fixture.owner) }
        await observer.release()
        await #expect(throws: (any Error).self) { try await saving.value }
        #expect(try await fixture.archive.withGeneration { $0?.revision == 1 })
        #expect(await fixture.governor.usage(.admittedMemoryBytes) <= before)
        await fixture.runtime.stop()
    }

    @Test func cancellationAfterCaptureReleasesStagingBeforeBackendSaveAndRefundsOutput() async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        let image = try await fixture.runtime.importAsset(
            encoded      : archiveSavePNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        try await fixture.publish(
            [fixture.publication(asset: image.assetID)],
            sequence: 1
        )
        // Keep the real 64 MiB provider reservation active during the complete save pipeline.
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        let before = await fixture.governor.usage(.admittedMemoryBytes)
        await observer.arm(after: 2)
        let saving = Task {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await observer.waitForArrival()
        let parked = await fixture.governor.usage(.admittedMemoryBytes)
        // Only bounded output and backend save workspace should remain. Retaining the 18 MiB
        // capture scope here would exceed this deliberately generous small-fixture threshold.
        #expect(parked > before)
        #expect(parked - before < 24 * 1_024 * 1_024)
        saving.cancel()
        await observer.release()
        await #expect(throws: (any Error).self) { try await saving.value }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == before)
        #expect(try await fixture.archive.withGeneration { $0?.revision == 1 })
        await fixture.stop()
    }

    @Test(arguments: ["cancel", "disable", "stop"])
    func knownCommittedSaveSurvivesLaterLifecycleChange(_ change: String) async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        await observer.arm(after: 3)
        let saving = Task {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await observer.waitForArrival()
        switch change {
        case "cancel": saving.cancel()
        case "disable": await fixture.runtime.disable(owner: fixture.owner)
        default: await fixture.runtime.stop()
        }
        await observer.release()
        #expect(try await saving.value.revision == 2)
        #expect(try await fixture.archive.withGeneration { $0?.revision == 2 })
        await fixture.runtime.stop()
    }

    @Test
    func busyAdmissionRefusalDoesNotConsumeThePendingMarker() async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        await observer.arm(after: 0)
        let explicitSave = Task {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await observer.waitForArrival()
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        explicitSave.cancel()
        await observer.release()
        await #expect(throws: (any Error).self) { try await explicitSave.value }
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity) == .pending
        )
        #expect(
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )?.revision == 1
        )
        await fixture.stop()
    }

    @Test(arguments: [3, 4])
    func pendingSaveAcknowledgesTheCanonicalCaptureRatherThanSelectionOrReturn(_ gateIndex: Int) async throws
    {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        await observer.arm(after: gateIndex)
        let saving = Task {
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await observer.waitForArrival()
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(100),
                monotonic: .seconds(100)
            )
        )
        // Expiry is synchronous before serviceDeadlines attempts its next admission. That later
        // admission may reject while this save is parked, without undoing canonical expiry.
        _ = try? await fixture.runtime.serviceDeadlines()
        await observer.release()
        #expect(try await saving.value?.revision == 1)
        // Drop the provider reservation before the independent protected archive-inspection scope.
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity)
                == (gateIndex == 3 ? .clean : .pending)
        )
        #expect(
            try await fixture.matches { envelope in
                envelope.records.count == 1 && (envelope.records[0].publication == nil) == (gateIndex == 3)
            }
        )
        if gateIndex == 4 {
            #expect(
                try await fixture.runtime.savePendingArchive(
                    owner: fixture.owner,
                    to   : fixture.archive
                )?.revision == 2
            )
            #expect(try await fixture.matches { $0.records.count == 1 && $0.records[0].publication == nil })
        }
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity) == .clean
        )
        await fixture.stop()
    }

    @Test
    func failedReplacementIsSuppressedAndPreservesThePreviouslySavedGeneration() async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        #expect(
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )?.revision == 1
        )
        try await fixture.publish(
            [fixture.publication(revision: 2)],
            sequence: 2
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        let before = await fixture.governor.usage(.retainedStateBytes)
        let filler = try await fixture.governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - before - 1_024),
            owner: fixture.owner
        )
        await #expect(throws: (any Error).self) {
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity)
                == .retryRequired
        )
        for _ in 0..<4 {
            #expect(
                try await fixture.runtime.savePendingArchive(
                    owner: fixture.owner,
                    to   : fixture.archive
                ) == nil
            )
        }
        try await fixture.governor.release(
            filler.id,
            owner: fixture.owner
        )
        #expect(await fixture.governor.usage(.retainedStateBytes) == before)
        #expect(try await fixture.matches { $0.records.first?.revision == 1 })
        #expect(
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            ).revision == 2
        )
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity) == .clean
        )
        #expect(try await fixture.matches { $0.records.first?.revision == 2 })
        await fixture.stop()
    }

    @Test(arguments: [false, true])
    func pendingSaveRevocationRespectsTheKnownCommitBoundary(_ committed: Bool) async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        await observer.arm(after: committed ? 5 : 3)
        let saving = Task {
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await observer.waitForArrival()
        await fixture.runtime.disable(owner: fixture.owner)
        await observer.release()
        if committed {
            #expect(try await saving.value?.revision == 1)
        } else {
            await #expect(throws: (any Error).self) { try await saving.value }
        }
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity)
                == .unavailable
        )
        #expect(try await fixture.archive.withGeneration { ($0 != nil) == committed })
        await fixture.stop()
    }

    @Test
    func unpublishedImageAliasesAndActionCompletionDoNotDirtyTheCanonicalArchive() async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        let image = try await fixture.runtime.importAsset(
            encoded      : archiveSavePNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity) == .clean
        )
        try await fixture.runtime.releaseAsset(
            assetID      : image.assetID,
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity) == .clean
        )
        let publication = try Publication(
            id         : fixture.ids[0],
            revision   : 1,
            kind       : .widget,
            content    : ActionFixture().presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        try await fixture.publish(
            [publication],
            sequence: 1
        )
        _ = try await fixture.runtime.savePendingArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        let action = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : fixture.ids[0],
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await fixture.runtime.submitAction(action)
        _ = try await fixture.runtime.pumpReady()
        let delivery = try #require(fixture.adapter.lastAction)
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                delivery,
                connection: fixture.connection,
                outcome   : .completed(payload: Data())
            )
        )
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity) == .clean
        )
        #expect(
            try await fixture.runtime.savePendingArchive(
                owner: fixture.owner,
                to   : fixture.archive
            ) == nil
        )
        await fixture.stop()
    }


}

/// ArchiveSaveFixture composes real runtime, native decoding, governor and SwiftData with fake transport only.
struct ArchiveSaveFixture: Sendable {
    let runtime   : AddonRuntime
    let governor  : ResourceGovernor
    let adapter   : RecordingRuntimeAdapter
    let clock     : MutableRuntimeClock
    let installed : InstalledAddon
    let ids       : [PublicationID]
    let connection: RuntimeConnection
    let archive   : SwiftDataArchive
    let root      : URL
    let wall      : Date
    var owner     : AddonID { installed.manifest.id }

    static func make(
        partitions: [AssetPrivacyPartition] = [.addonOwned],
        observer  : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver()
    ) async throws -> Self {
        let base      = try ActionFixture()
        let installed = try base.context().installed
        let governor  = ResourceGovernor()
        let adapter   = RecordingRuntimeAdapter()
        let clock     = MutableRuntimeClock(
            instant: RuntimeInstant(
                wall     : base.wall,
                monotonic: .zero
            )
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [installed],
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
            governor: governor,
            adapter : adapter,
            clock   : clock
        )
        var ids: [PublicationID] = []
        for (index, partition) in partitions.enumerated() {
            ids.append(
                try await runtime.assignPublication(
                    owner                : base.owner,
                    featureID            : index == 0 ? "controls" : "other",
                    instanceID           : UUID(),
                    assetPrivacyPartition: partition
                )
            )
        }
        let launch     = try await runtime.requestLaunch(owner: base.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let root = URL(fileURLWithPath: "/private/tmp/cascade-runtime-save-\(UUID())")
        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let archive = try await SwiftDataArchive.make(
            identity: installed.verifiedIdentity,
            root    : root,
            governor: governor,
            observer: observer
        )
        _ = try await archive.start()
        return Self(
            runtime   : runtime,
            governor  : governor,
            adapter   : adapter,
            clock     : clock,
            installed : installed,
            ids       : ids,
            connection: connection,
            archive   : archive,
            root      : root,
            wall      : base.wall
        )
    }

    func content(
        text : String = "Image",
        asset: String? = nil
    ) throws -> PresentationSet {
        try PresentationSet(
            widget: ContentDocument(
                root              : .text(text),
                privacy           : .publicContent,
                accessibilityLabel: text,
                assetIDs          : asset.map { [$0] } ?? []
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    func publication(
        index   : Int = 0,
        asset   : String? = nil,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : ids[index],
            revision   : revision,
            kind       : .widget,
            content    : content(asset: asset),
            timeline   : nil,
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
    }

    func publish(
        _ publications: [Publication],
        sequence      : UInt64,
        ends          : [PublicationID] = []
    ) async throws {
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : sequence
        )
    }

    /// matches keeps decoded leaves and one graph inside admitted scopes and returns only a Boolean.
    func matches(_ check: @Sendable (RuntimeArchiveEnvelope) throws -> Bool) async throws -> Bool {
        try await archive.withGeneration { generation in
            guard let generation else { return false }
            return try await governor.withAssetDecodeReservation(
                bytes: RuntimeArchiveEnvelope.retentionReservationBytes() + generation.payload.count,
                owner: owner
            ) {
                let envelope = try RuntimeArchiveEnvelope.decode(generation.payload)
                return try await governor.withAssetDecodeReservation(
                    bytes: RuntimeArchivePublicationCodec.inspectionReservationBytes(),
                    owner: owner
                ) { try check(envelope) }
            }
        }
    }

    func stop() async {
        await runtime.stop()
        await runtime.observeExit(connection.incarnation)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

func archiveSavePNG() throws -> Data {
    let bytes    = NSMutableData()
    let provider = try #require(CGDataProvider(data: Data([255, 0, 0, 255]) as CFData))
    let color    = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let image    = try #require(
        CGImage(
            width            : 1,
            height           : 1,
            bitsPerComponent : 8,
            bitsPerPixel     : 32,
            bytesPerRow      : 4,
            space            : color,
            bitmapInfo       : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider         : provider,
            decode           : nil,
            shouldInterpolate: false,
            intent           : .defaultIntent
        )
    )
    let destination = try #require(
        CGImageDestinationCreateWithData(
            bytes,
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
    return bytes as Data
}

/// SaveArchiveObserver gates the return of a real filesystem inventory at a chosen operation boundary.
actor SaveArchiveObserver: SwiftDataArchiveObserving {
    private var countdown: Int?
    private var hasArrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var resume : CheckedContinuation<Void, Never>?

    func arm(after count: Int) {
        countdown = count
        hasArrived = false
    }

    func waitForArrival() async {
        if !hasArrived { await withCheckedContinuation { arrival = $0 } }
    }

    func release() {
        resume?.resume()
        resume = nil
    }

    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let result = await NativeSwiftDataArchiveObserver().inventory(
            root      : root,
            descriptor: descriptor
        )
        if let countdown {
            if countdown == 0 {
                self.countdown = nil
                hasArrived = true
                arrival?.resume()
                arrival = nil
                await withCheckedContinuation { resume = $0 }
            } else {
                self.countdown = countdown - 1
            }
        }
        return result
    }
}
