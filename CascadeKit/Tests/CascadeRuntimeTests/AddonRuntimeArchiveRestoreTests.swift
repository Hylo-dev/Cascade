//
//  AddonRuntimeArchiveRestoreTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonRuntimeArchiveRestoreTests {
    @Test
    func restoresRealSavedRevisionZeroAndAllFutureTimelineEntries() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let source = try await fixture.runtime()
        let id = try await source.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let connection = try await fixture.connect(source)
        let content = try fixture.publication(
            id    : id,
            future: true
        )
        try await fixture.publish(
            source,
            connection  : connection,
            publications: [content]
        )
        await source.observeExit(connection.incarnation)
        _ = try await source.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        await source.stop()
        let target = try await fixture.runtime()
        #expect(try await target.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .restored(
            revision: 1,
            active  : 1,
            terminal: 0
        ))
        #expect(await target.snapshot(at: fixture.wall.addingTimeInterval(1)).publications.count == 1)
        #expect(await target.snapshot(at: fixture.wall.addingTimeInterval(30)).publications.first?.revision == 0)
        let recovered = try await target.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: id.instanceID
        )
        #expect(recovered == id)
        await target.stop()
    }

    @Test
    func absentGenerationDoesNotSealButCommittedEmptyGenerationDoes() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let runtime = try await fixture.runtime()
        #expect(try await runtime.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .empty)
        try await fixture.write(records: [])
        #expect(try await runtime.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .restored(
            revision: 1,
            active  : 0,
            terminal: 0
        ))
        await #expect(throws: AddonFailure.self) {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        await runtime.stop()
    }

    @Test
    func acceptedLaunchAndAssignmentSealRestorationAfterExit() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.write(records: [])
        for assignmentFirst in [false, true] {
            let runtime = try await fixture.runtime()
            if assignmentFirst {
                _ = try await runtime.assignPublication(
                    owner     : fixture.owner,
                    featureID : "controls",
                    instanceID: UUID()
                )
            } else {
                _ = try await runtime.requestLaunch(owner: fixture.owner)
                let start = try #require(fixture.adapter.lastStart(owner: fixture.owner))
                await runtime.observeExit(start.incarnation)
            }
            await #expect(throws: AddonFailure.self) {
                try await runtime.restoreArchive(
                    owner: fixture.owner,
                    from : fixture.archive
                )
            }
            await runtime.stop()
        }
    }
    @Test(arguments: ["cancel", "rollback", "expiry", "cleanup"])
    func suspendedPoolAdmissionKeepsFixedClockAndPrepaidMetadata(_ interruption: String) async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let id = fixture.newID()
        let publication = try fixture.publication(id: id)
        try await fixture.write(records: [fixture.record(publication)])
        let access = GatedRuntimeResourceAccess(target: fixture.governor)
        let runtime = try await fixture.runtime(access: access)
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let beforeState = await fixture.governor.usage(.retainedStateBytes)
        let beforePool = try #require(await runtime.diagnostics(owner: fixture.owner)).reservedStateBytes
        await access.armResize()
        let restoring = Task {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        await access.waitForArrival()
        switch interruption {
        case "cancel": restoring.cancel()
        case "rollback":
            fixture.clock.set(RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(-1),
                monotonic: .zero
            ))
        case "expiry":
            fixture.clock.set(RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(200),
                monotonic: .seconds(200)
            ))
        default:
            // This event performs canonical expiry/deferred marking before its nested admission fails.
            _ = try? await runtime.serviceDeadlines()
        }
        await access.releaseGate()
        if interruption == "cleanup" {
            #expect(try await restoring.value == .restored(
            revision: 1,
            active  : 1,
            terminal: 0
        ))
            let afterPool = try #require(await runtime.diagnostics(owner: fixture.owner)).reservedStateBytes
            #expect(afterPool == beforePool + 4_096 + (try JSONEncoder().encode(publication).count))
        } else {
            await #expect(throws: (any Error).self) { try await restoring.value }
            #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
            #expect(await fixture.governor.usage(.retainedStateBytes) == beforeState)
            fixture.clock.set(RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            ))
            #expect(try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            ) == .restored(
            revision: 1,
            active  : 1,
            terminal: 0
        ))
        }
        await runtime.stop()
    }

    @Test(arguments: ["memory", "state", "family", "raster"])
    func realQuotaDenialLeavesAllCanonicalStateUnchangedAndCanRetry(_ dimension: String) async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let id = fixture.newID()
        let publication = try fixture.imagePublication(id: id)
        let blob = UUID()
        let otherBlob = UUID()
        let other = try fixture.imagePublication(id: fixture.newID())
        try await fixture.write(
            records: [
                fixture.record(
                    publication,
                    blob: blob
                ),
                fixture.record(
                    other,
                    blob: otherBlob
                ),
            ],
            blobs  : [fixture.blob(blob), fixture.blob(otherBlob)]
        )
        let runtime = try await fixture.runtime()
        let baselineMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let baselineState = await fixture.governor.usage(.retainedStateBytes)
        var fillers: [ResourceReservation] = []
        switch dimension {
        case "memory":
            fillers.append(try await fixture.governor.admit(
                .temporaryMemory(bytes: 128 * 1_024 * 1_024 - baselineMemory),
                owner: fixture.owner
            ))
        case "state":
            fillers.append(try await fixture.governor.admit(
                .state(bytes: 8 * 1_024 * 1_024 - baselineState - 1_024),
                owner: fixture.owner
            ))
        case "family":
            for _ in 0..<16 {
                fillers.append(try await fixture.governor.admit(
                    .publication(.widget),
                    owner: fixture.owner
                ))
            }
        default:
            fillers.append(try await fixture.governor.admit(
                .asset(bytes: 8 * 1_024 * 1_024 - 4),
                owner: fixture.owner
            ))
        }
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let beforeState = await fixture.governor.usage(.retainedStateBytes)
        await #expect(throws: AddonFailure.self) {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        #expect(await fixture.governor.usage(.retainedStateBytes) == beforeState)
        for filler in fillers {
            try await fixture.governor.release(
                filler.id,
                owner: fixture.owner
            )
        }
        #expect(try await runtime.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .restored(
            revision: 1,
            active  : 2,
            terminal: 0
        ))
        #expect(await fixture.governor.usage(.assetBytes) == 8)
        await runtime.stop()
    }

    @Test
    func terminalAndElapsedRecordsKeepAssignmentsThroughPoolShrinkWithoutAllocatingPixels() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let publication = try fixture.imagePublication(id: fixture.newID())
        let blob = UUID()
        let ended = RuntimeArchiveEnvelope.Record(
            instance       : RuntimeArchiveEnvelope.uuidBytes(UUID()),
            session        : RuntimeArchiveEnvelope.uuidBytes(UUID()),
            feature        : Data("controls".utf8),
            partition      : nil,
            revision       : UInt64.max,
            kind           : .widget,
            sessionDeadline: fixture.wall.addingTimeInterval(100),
            publication    : nil,
            aliases        : []
        )
        try await fixture.write(
            records: [
                fixture.record(
                    publication,
                    blob: blob
                ),
                ended,
            ],
            blobs  : [fixture.blob(blob)]
        )
        fixture.clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(200),
            monotonic: .seconds(200)
        ))
        let runtime = try await fixture.runtime()
        let before = try #require(await runtime.diagnostics(owner: fixture.owner)).reservedStateBytes
        let filler = try await fixture.governor.admit(
            .asset(bytes: 8 * 1_024 * 1_024),
            owner: fixture.owner
        )
        #expect(try await runtime.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .restored(
            revision: 1,
            active  : 0,
            terminal: 2
        ))
        #expect(await runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before + 7_168)
        #expect(await fixture.governor.usage(.assetBytes) == 8 * 1_024 * 1_024)
        #expect(await fixture.governor.usage(.publications) == 0)
        try await fixture.governor.release(
            filler.id,
            owner: fixture.owner
        )
        _ = try await runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(try await fixture.matches { envelope in
            envelope.records.count == 2 && envelope.blobs.isEmpty
                && envelope.records.allSatisfy { $0.publication == nil && $0.aliases.isEmpty }
        })
        _ = try await runtime.serviceDeadlines()
        await #expect(throws: AddonFailure.self) {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        await runtime.stop()
    }

    @Test(arguments: ["feature", "revision", "anchor", "instance"])
    func malformedLaterMemberRejectsTheWholeBatchBeforeActivation(_ mismatch: String) async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let first = try fixture.publication(id: fixture.newID())
        let secondID = PublicationID(
            addonID   : fixture.owner,
            instanceID: mismatch == "instance" ? first.id.instanceID : UUID(),
            sessionID : UUID()
        )
        let second = try fixture.publication(id: secondID)
        let later = try fixture.record(
            second,
            feature : mismatch == "feature" ? "missing" : "controls",
            revision: mismatch == "revision" ? 9 : second.revision,
            deadline: mismatch == "anchor" ? fixture.wall : nil
        )
        if mismatch == "instance" {
            await #expect(throws: AddonFailure.self) {
                try await fixture.write(records: [fixture.record(first), later])
            }
            #expect(try await fixture.archive.withGeneration { $0 == nil })
            return
        }
        try await fixture.write(records: [fixture.record(first), later])
        let runtime = try await fixture.runtime()
        let before = await fixture.governor.usage(.retainedStateBytes)
        await #expect(throws: AddonFailure.self) {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)
        #expect(await fixture.governor.usage(.retainedStateBytes) == before)
        #expect(await fixture.governor.usage(.publications) == 0)
        await runtime.stop()
    }

    @Test
    func declinedStartLeavesRestorationAvailable() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.write(records: [])
        let runtime = try await fixture.runtime(
            adapter: RecordingRuntimeAdapter(rejectedStartOwners: [fixture.owner])
        )
        await #expect(throws: AddonFailure.self) { try await runtime.requestLaunch(owner: fixture.owner) }
        #expect(try await runtime.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .restored(
            revision: 1,
            active  : 0,
            terminal: 0
        ))
        await runtime.stop()
    }

    @Test
    func metadataQuotesAreCheckedAndDoNotCreateNamespaceOrPins() throws {
        let identity = try ActionFixture().context().installed.verifiedIdentity
        let publications = PublicationState()
        let assets = AssetState()
        for count in [-1, Int.max] {
            #expect(throws: AddonFailure.self) {
                try publications.restorationMetadataBytes(
                    recordCount: count,
                    identity   : identity
                )
            }
            #expect(throws: AddonFailure.self) {
                try assets.restorationMetadataBytes(
                    bindingCount: count,
                    aliasCount  : count
                )
            }
        }
        #expect(try publications.restorationMetadataBytes(
            recordCount: 2,
            identity   : identity
        ) == 3_072)
        #expect(try assets.restorationMetadataBytes(
            bindingCount: 2,
            aliasCount  : 3
        ) == 7_168)
        #expect(publications.retainedBytes == 0)
        #expect(publications.sessionAccounting(owner: identity.addonID).namespaceBytes == 0)
        #expect(assets.retainedBytes == 0)
    }

    @Test
    func sharedNativePixelsGetFreshAliasesAndPartitionsWhileFullFieldsSurvive() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let first = try fixture.imagePublication(
            id  : fixture.newID(),
            rich: true
        )
        let second = try fixture.imagePublication(id: fixture.newID())
        let blobID = UUID()
        let oldPartition = UUID()
        try await fixture.write(
            records: [
                fixture.record(
                    first,
                    blob     : blobID,
                    partition: oldPartition
                ),
                fixture.record(
                    second,
                    blob     : blobID,
                    partition: oldPartition
                ),
            ],
            blobs: [fixture.blob(
                blobID,
                partition: oldPartition
            )]
        )
        let runtime = try await fixture.runtime()
        #expect(try await runtime.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        ) == .restored(
            revision: 1,
            active  : 2,
            terminal: 0
        ))
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        let snapshot = await runtime.snapshot(at: fixture.wall)
        let firstRestored = try #require(snapshot.publications.first(where: { $0.id == first.id }))
        let secondRestored = try #require(snapshot.publications.first(where: { $0.id == second.id }))
        let firstAlias = try #require(firstRestored.content?.widget?.assets.first)
        let secondAlias = try #require(secondRestored.content?.widget?.assets.first)
        #expect(firstAlias != "old" && secondAlias != "old" && firstAlias != secondAlias)
        var borrowed = await runtime.assetImage(
            assetID            : firstAlias,
            publicationID      : first.id,
            publicationRevision: 0
        )
        #expect(borrowed?.dataProvider?.data as Data? == Data([255, 0, 0, 255]))
        #expect(await runtime.assetImage(
            assetID            : "old",
            publicationID      : first.id,
            publicationRevision: 0
        ) == nil)
        _ = try await runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        #expect(try await fixture.matches { envelope in
            guard envelope.blobs.count == 1, envelope.records.count == 2,
                  envelope.records.allSatisfy({ $0.partition != RuntimeArchiveEnvelope.uuidBytes(oldPartition) }),
                  Set(envelope.records.map(\.partition)).count == 1,
                  let record = envelope.records.first(where: { $0.kind == .activity }),
                  let json = record.publication else { return false }
            let restored = try RuntimeArchivePublicationCodec.decode(json)
            guard restored.timeline?.map(\.date) == first.timeline?.map(\.date),
                  restored.revision == 0, restored.expiresAt == first.expiresAt,
                  record.sessionDeadline == fixture.wall.addingTimeInterval(8 * 3_600),
                  restored.stalePolicy == first.stalePolicy else { return false }
            for entry in restored.timeline ?? [] {
                for document in [entry.content.widget, entry.content.compactLeading,
                                 entry.content.compactTrailing, entry.content.minimal, entry.content.expanded] {
                    guard let document,
                          document.schemaVersion == 2,
                          document.privacy == .sensitive,
                          document.glassLights == first.timeline?.first?.content.widget?.glassLights,
                          document.accessibilityLabel == "Archive image",
                          document.assets == [firstAlias],
                          document.root.children?.first?.assetID == firstAlias,
                          document.root.children?.first?.accessibilityLabel == "Red pixel",
                          document.root.children?[1].actionPayload == Data([7, 9]),
                          document.root.children?[1].actionID == "pause",
                          document.root.children?[1].text == "Pause",
                          document.root.children?[2].clockFormat == .hourMinuteSecond else { return false }
                }
            }
            return true
        })
        await runtime.stop()
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(borrowed?.width == 1)
        let next = try await fixture.runtime()
        _ = try await next.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        )
        #expect(await fixture.governor.usage(.assetBytes) == 8)
        borrowed = nil
        await next.stop()
    }

    @Test
    func originalActivityAnchorSurvivesHigherRevisionAndPrunedHistoryCannotReplay() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let document = try ContentDocument(
            root              : .text("Activity"),
            privacy           : .publicContent,
            accessibilityLabel: "Activity",
            assetIDs          : []
        )
        let presentation = try PresentationSet(
            widget         : nil,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : document
        )
        let source = try await fixture.runtime()
        let id = try await source.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let sourceConnection = try await fixture.connect(source)
        let original = try Publication(
            id         : id,
            revision   : 0,
            kind       : .activity,
            content    : presentation,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(8 * 3_600),
            stalePolicy: .retainMarked
        )
        try await fixture.publish(
            source,
            connection  : sourceConnection,
            publications: [original]
        )
        await source.observeExit(sourceConnection.incarnation)
        _ = try await source.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        await source.stop()
        fixture.clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(3_600),
            monotonic: .seconds(3_600)
        ))
        let target = try await fixture.runtime()
        _ = try await target.restoreArchive(
            owner: fixture.owner,
            from : fixture.archive
        )
        let targetConnection = try await fixture.connect(target)
        let updated = try Publication(
            id         : id,
            revision   : 1,
            kind       : .activity,
            content    : presentation,
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(12 * 3_600),
            stalePolicy: .retainMarked
        )
        try await fixture.publish(
            target,
            connection  : targetConnection,
            publications: [updated]
        )
        let live = await target.snapshot(at: fixture.wall.addingTimeInterval(3_600)).publications.first
        #expect(live?.id == id)
        #expect(live?.revision == 1)
        #expect(live?.expiresAt == fixture.wall.addingTimeInterval(8 * 3_600))
        try await fixture.publish(
            target,
            connection  : targetConnection,
            publications: [],
            sequence    : 2,
            ends        : [id]
        )
        await target.observeExit(targetConnection.incarnation)
        _ = try await target.serviceDeadlines()
        #expect(await target.snapshot(at: fixture.wall).publications.isEmpty)
        await #expect(throws: AddonFailure.self) {
            try await target.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        await target.stop()
    }

    @Test
    func rollbackDoesNotReactivateUnquotedElapsedContentBeforeCanonicalValidation() async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        let publication = try fixture.publication(id: fixture.newID())
        try await fixture.write(records: [fixture.record(publication)])
        fixture.clock.set(RuntimeInstant(
            wall     : fixture.wall.addingTimeInterval(200),
            monotonic: .seconds(200)
        ))
        let access = GatedRuntimeResourceAccess(target: fixture.governor)
        let runtime = try await fixture.runtime(access: access)
        var families: [ResourceReservation] = []
        for _ in 0..<16 {
            families.append(try await fixture.governor.admit(
                .publication(.widget),
                owner: fixture.owner
            ))
        }
        await access.armResize()
        let restoring = Task {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : fixture.archive
            )
        }
        await access.waitForArrival()
        fixture.clock.set(RuntimeInstant(
            wall     : fixture.wall,
            monotonic: .zero
        ))
        await access.releaseGate()
        do {
            _ = try await restoring.value
            Issue.record("Clock rollback unexpectedly activated the elapsed generation.")
        } catch let failure as AddonFailure {
            // Sampling a new prepare timestamp would attempt unquoted live family admission and
            // fail resourceDenied against the real full quota before reaching final clock validation.
            #expect(failure.code == .deadlineExceeded)
        }
        #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)
        for reservation in families {
            try await fixture.governor.release(
                reservation.id,
                owner: fixture.owner
            )
        }
        await runtime.stop()
    }

    @Test(arguments: ["owner", "publisher", "governor", "digest"])
    func currentHostAndBackendBindingRejectForeignArchives(_ mismatch: String) async throws {
        let fixture = try await ArchiveRestoreFixture.make()
        defer { fixture.removeFiles() }
        if mismatch == "digest" {
            try await fixture.write(records: [])
            let current = try ActionFixture().context(digest: "replacement-artifact").installed
            let runtime = try await fixture.runtime(installed: current)
            await #expect(throws: AddonFailure.self) {
                try await runtime.restoreArchive(
                    owner: fixture.owner,
                    from : fixture.archive
                )
            }
            await runtime.stop()
            return
        }
        let root = fixture.root.appendingPathComponent("foreign")
        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let identity = try VerifiedAddonIdentity(
            publisher: mismatch == "publisher" ? "foreign.publisher" : fixture.installed.verifiedIdentity.publisher,
            addonID  : mismatch == "owner" ? #require(AddonID(rawValue: "com.example.foreign")) : fixture.owner
        )
        let archive = try await SwiftDataArchive.make(
            identity: identity,
            root    : root,
            governor: mismatch == "governor" ? ResourceGovernor() : fixture.governor
        )
        let runtime = try await fixture.runtime()
        let before = await fixture.governor.usage(.admittedMemoryBytes)
        await #expect(throws: AddonFailure.self) {
            try await runtime.restoreArchive(
                owner: fixture.owner,
                from : archive
            )
        }
        #expect(await archive.status().state == .unavailable)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == before)
        await runtime.stop()
    }

    @Test
    func acceptedIndirectPrefixStaysSealedAfterLaterStartDeclines() async throws {
        let consumer = try installedFixture(
            "consumer",
            publisher: "shared.publisher"
        )
        let base = try installedFixture(
            "focus",
            publisher: "shared.publisher"
        )
        let leaf = try replacing(
            base,
            id      : "com.example.archive.leaf",
            requires: [],
            provides: [ProvidedService(
                kind   : .service,
                id     : "com.example.archive.dependency",
                version: "1.0.0"
            )]
        )
        let provider = try replacing(
            base,
            id      : "com.example.archive.provider",
            requires: [requirement(
                "com.example.archive.dependency",
                ">=1.0.0 <2.0.0"
            )]
        )
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter(rejectedStartOwners: [provider.manifest.id])
        let runtime = try await AddonRuntime.make(
            catalog    : [consumer, provider, leaf],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [consumer.manifest.id: [], provider.manifest.id: [], leaf.manifest.id: []],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : FixedRuntimeClock(instant: RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000),
                monotonic: .zero
            ))
        )
        let launch = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let permission = try await runtime.authorizeService(
            connection           : connection,
            requirementID        : "com.example.focus.sessions",
            scope                : ServiceScope(
                featureID: "summary",
                operation: "read"
            ),
            partition            : "account-a",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : connection,
                permissionID: permission,
                lifetime    : .seconds(30)
            )
        }
        let started = try #require(adapter.lastStart(owner: leaf.manifest.id))
        await runtime.observeExit(started.incarnation)
        for installed in [leaf, provider] {
            let root = URL(fileURLWithPath: "/private/tmp/cascade-archive-prefix-\(UUID())")
            try FileManager.default.createDirectory(
                at                         : root,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = try await SwiftDataArchive.make(
                identity: installed.verifiedIdentity,
                root    : root,
                governor: governor
            )
            _ = try await archive.start()
            try await governor.withAssetDecodeReservation(
                bytes: 32 * 1_024 * 1_024,
                owner: installed.manifest.id
            ) {
                let envelope = RuntimeArchiveEnvelope(
                    publisher: Data(installed.verifiedIdentity.publisher.utf8),
                    addon    : Data(installed.manifest.id.rawValue.utf8),
                    digest   : Data(installed.digest.utf8),
                    records  : [],
                    blobs    : []
                )
                _ = try await archive.save(
                    SwiftDataArchiveGeneration(
                        schemaVersion : 1,
                        revision      : 1,
                        verifiedDigest: installed.digest,
                        payload       : envelope.encode()
                    ),
                    replacing: nil
                )
            }
            if installed.manifest.id == leaf.manifest.id {
                await #expect(throws: AddonFailure.self) {
                    try await runtime.restoreArchive(
                        owner: installed.manifest.id,
                        from : archive
                    )
                }
            } else {
                #expect(try await runtime.restoreArchive(
                    owner: installed.manifest.id,
                    from : archive
                ) == .restored(
            revision: 1,
            active  : 0,
            terminal: 0
        ))
            }
        }
        await runtime.stop()
        await runtime.observeExit(connection.incarnation)
    }

}

/// ArchiveRestoreFixture uses real shared-governor archives and fresh runtimes with fake transport only.
private struct ArchiveRestoreFixture: Sendable {
    let installed: InstalledAddon
    let governor : ResourceGovernor
    let adapter  : RecordingRuntimeAdapter
    let clock    : MutableRuntimeClock
    let archive  : SwiftDataArchive
    let root     : URL
    let wall     : Date
    var owner: AddonID { installed.manifest.id }

    static func make() async throws -> Self {
        let base = try ActionFixture()
        let installed = try base.context().installed
        let governor = ResourceGovernor()
        let root = URL(fileURLWithPath: "/private/tmp/cascade-runtime-restore-\(UUID())")
        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let archive = try await SwiftDataArchive.make(
            identity: installed.verifiedIdentity,
            root    : root,
            governor: governor
        )
        _ = try await archive.start()
        return Self(
            installed: installed,
            governor : governor,
            adapter  : RecordingRuntimeAdapter(),
            clock    : MutableRuntimeClock(instant: RuntimeInstant(
                wall     : base.wall,
                monotonic: .zero
            )),
            archive  : archive,
            root     : root,
            wall     : base.wall
        )
    }

    func runtime(
        access   : (any RuntimeResourceAccess)? = nil,
        adapter  : RecordingRuntimeAdapter? = nil,
        installed: InstalledAddon? = nil
    ) async throws -> AddonRuntime {
        try await AddonRuntime.make(
            catalog    : [installed ?? self.installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [owner: []],
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : access ?? governor,
            serviceDecisionFactory: { $0 },
            adapter               : adapter ?? self.adapter,
            clock                 : clock
        )
    }

    func connect(_ runtime: AddonRuntime) async throws -> RuntimeConnection {
        let launch = try await runtime.requestLaunch(owner: owner)
        return try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1, 2]
            )
        )
    }

    func publication(
        id    : PublicationID,
        future: Bool = false
    ) throws -> Publication {
        func presentation(_ text: String) throws -> PresentationSet {
            try PresentationSet(
                widget         : ContentDocument(
                    root              : .text(text),
                    privacy           : .publicContent,
                    accessibilityLabel: text,
                    assetIDs          : []
                ),
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            )
        }
        return try Publication(
            id         : id,
            revision   : 0,
            kind       : .widget,
            content    : future ? nil : presentation("Current"),
            timeline   : future ? [
                ScheduledEntry(
                    date   : wall,
                    content: presentation("First")
                ),
                ScheduledEntry(
                    date   : wall.addingTimeInterval(20),
                    content: presentation("Future")
                ),
            ] : nil,
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
    }

    func publish(
        _ runtime   : AddonRuntime,
        connection  : RuntimeConnection,
        publications: [Publication],
        sequence    : UInt64 = 1,
        ends        : [PublicationID] = []
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

    func write(
        records: [RuntimeArchiveEnvelope.Record],
        blobs  : [RuntimeArchiveEnvelope.Blob] = []
    ) async throws {
        try await governor.withAssetDecodeReservation(
            bytes: RuntimeArchiveEnvelope.retentionReservationBytes() + 16 * 1_024 * 1_024,
            owner: owner
        ) {
            let envelope = RuntimeArchiveEnvelope(
                publisher: Data(installed.verifiedIdentity.publisher.utf8),
                addon    : Data(owner.rawValue.utf8),
                digest   : Data(installed.digest.utf8),
                records  : records,
                blobs    : blobs
            )
            _ = try await archive.save(
                SwiftDataArchiveGeneration(
                    schemaVersion : 1,
                    revision      : 1,
                    verifiedDigest: installed.digest,
                    payload       : envelope.encode()
                ),
                replacing: nil
            )
        }
    }

    func newID() -> PublicationID {
        PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    func record(
        _ publication: Publication,
        blob         : UUID? = nil,
        partition    : UUID? = nil,
        feature      : String = "controls",
        revision     : UInt64? = nil,
        deadline     : Date? = nil
    ) throws -> RuntimeArchiveEnvelope.Record {
        try RuntimeArchiveEnvelope.Record(
            instance       : RuntimeArchiveEnvelope.uuidBytes(publication.id.instanceID),
            session        : RuntimeArchiveEnvelope.uuidBytes(publication.id.sessionID),
            feature        : Data(feature.utf8),
            partition      : partition.map(RuntimeArchiveEnvelope.uuidBytes),
            revision       : revision ?? publication.revision,
            kind           : publication.kind,
            sessionDeadline: deadline ?? wall.addingTimeInterval(8 * 3_600),
            publication    : RuntimeArchivePublicationCodec.encode(publication),
            aliases        : blob.map { [RuntimeArchiveEnvelope.Alias(
                name: Data("old".utf8),
                blob: RuntimeArchiveEnvelope.uuidBytes($0)
            )] } ?? []
        )
    }

    func blob(
        _ id     : UUID,
        partition: UUID? = nil
    ) -> RuntimeArchiveEnvelope.Blob {
        RuntimeArchiveEnvelope.Blob(
            id       : RuntimeArchiveEnvelope.uuidBytes(id),
            partition: partition.map(RuntimeArchiveEnvelope.uuidBytes),
            width    : 1,
            height   : 1,
            pixels   : Data([255, 0, 0, 255])
        )
    }

    func imagePublication(
        id  : PublicationID,
        rich: Bool = false
    ) throws -> Publication {
        let image = try ContentNode(
            kind              : .image,
            text              : nil,
            assetID           : "old",
            value             : nil,
            deadline          : nil,
            actionID          : nil,
            children          : nil,
            accessibilityLabel: "Red pixel"
        )
        let action = try ContentNode(
            kind         : .action,
            text         : "Pause",
            assetID      : nil,
            value        : nil,
            deadline     : nil,
            actionID     : "pause",
            children     : nil,
            actionPayload: Data([7, 9])
        )
        let clock = try ContentNode(
            kind       : .clock,
            text       : nil,
            assetID    : nil,
            value      : nil,
            deadline   : nil,
            actionID   : nil,
            children   : nil,
            clockFormat: .hourMinuteSecond
        )
        let document = try ContentDocument(
            schemaVersion     : rich ? 2 : 1,
            root              : rich ? .column([image, action, clock]) : image,
            accessibilityLabel: "Archive image",
            privacy           : .sensitive,
            assets            : ["old"],
            glassLights       : rich ? [GlassLight(
                x        : 0.2,
                y        : 0.3,
                radius   : 0.5,
                red      : 1,
                green    : 0,
                blue     : 0,
                intensity: 0.8
            )] : nil
        )
        let presentation = try PresentationSet(
            widget         : document,
            compactLeading : document,
            compactTrailing: document,
            minimal        : document,
            expanded       : document
        )
        return try Publication(
            id         : id,
            revision   : 0,
            kind       : rich ? .activity : .widget,
            content    : rich ? nil : presentation,
            timeline   : rich ? [
                ScheduledEntry(
                    date   : wall,
                    content: presentation
                ),
                ScheduledEntry(
                    date   : wall.addingTimeInterval(30),
                    content: presentation
                ),
            ] : nil,
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
    }

    /// matches confines all decoded archive leaves and comparison graphs to protected test scopes.
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

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
