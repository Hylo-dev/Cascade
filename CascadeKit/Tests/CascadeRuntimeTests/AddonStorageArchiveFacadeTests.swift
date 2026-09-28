//
//  AddonStorageArchiveFacadeTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonStorageArchiveFacadeTests {
    @Test
    func realFacadeSaveAndFreshRuntimeRestorePreserveRevisionZeroAndFutureTimeline() async throws {
        let fixture = try await ArchiveFacadeFixture.make()
        defer { fixture.removeFiles() }
        let source = try await fixture.runtime()
        let id = try await fixture.publish(source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.archiveRoot.path).isEmpty)
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        #expect(try await fixture.coordinator.saveArchive(
            owner  : owner,
            runtime: source
        ).revision == 1)
        await source.stop()
        #expect(try await fixture.coordinator.close() == .closed)
        try await fixture.coordinator.start()
        let current = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        #expect(current != owner)
        let target = try await fixture.runtime()
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : current,
            runtime: target
        ) == .restored(
            revision: 1,
            active  : 1,
            terminal: 0
        ))
        let present = await target.snapshot(at: fixture.wall).publications
        #expect(present.first?.id == id)
        #expect(present.first?.revision == 0)
        #expect(present.first?.content?.widget?.root.text == "Now")
        let future = await target.snapshot(at: fixture.wall.addingTimeInterval(20)).publications
        #expect(future.first?.content?.widget?.root.text == "Future")
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 16_384)
        await target.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

    @Test
    func missingGenerationRemainsAvailableButSavedEmptyGenerationSealsRestoration() async throws {
        let fixture = try await ArchiveFacadeFixture.make()
        defer { fixture.removeFiles() }
        let runtime = try await fixture.runtime()
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : owner,
            runtime: runtime
        ) == .empty)
        #expect(try await fixture.coordinator.saveArchive(
            owner  : owner,
            runtime: runtime
        ).revision == 1)
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : owner,
            runtime: runtime
        ) == .restored(
            revision: 1,
            active  : 0,
            terminal: 0
        ))
        await #expect(throws: AddonFailure.self) {
            try await fixture.coordinator.restoreArchive(
                owner  : owner,
                runtime: runtime
            )
        }
        await runtime.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }
    @Test(arguments: ["foreignOwner", "staleOwner", "governor", "publisher", "owner", "disabled"])
    func rejectedBindingCannotProvisionAnAbsentArchive(mismatch: String) async throws {
        let fixture = try await ArchiveFacadeFixture.make()
        defer { fixture.removeFiles() }
        let foreign = try await ArchiveFacadeFixture.make()
        defer { foreign.removeFiles() }
        var capability = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        if mismatch == "foreignOwner" {
            capability = try await foreign.coordinator.owner(for: foreign.installed.verifiedIdentity)
        } else if mismatch == "staleOwner" {
            #expect(try await fixture.coordinator.close() == .closed)
            try await fixture.coordinator.start()
        }
        let installed: InstalledAddon
        switch mismatch {
        case "publisher": installed = try ActionFixture().context(publisher: "foreign.publisher").installed
        case "owner": installed = try ActionFixture(ownerName: "com.example.other-owner").context().installed
        case "disabled": installed = try ActionFixture().context(enabled: false).installed
        default: installed = fixture.installed
        }
        let runtime = try await fixture.runtime(
            governor : mismatch == "governor" ? ResourceGovernor() : nil,
            installed: installed
        )
        let memory = await fixture.governor.usage(.admittedMemoryBytes)
        let disk = await fixture.governor.usage(.diskBytes)
        for restoring in [false, true] {
            await #expect(throws: (any Error).self) {
                if restoring {
                    _ = try await fixture.coordinator.restoreArchive(
                        owner  : capability,
                        runtime: runtime
                    )
                } else {
                    _ = try await fixture.coordinator.saveArchive(
                        owner  : capability,
                        runtime: runtime
                    )
                }
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.archiveRoot.path).isEmpty)
            #expect(await fixture.governor.usage(.admittedMemoryBytes) == memory)
            #expect(await fixture.governor.usage(.diskBytes) == disk)
        }
        await runtime.stop()
        #expect(try await fixture.coordinator.close() == .closed)
        #expect(try await foreign.coordinator.close() == .closed)
    }

    @Test(arguments: [false, true])
    func interruptedLazyCreationRetainsLedgerButNeverCallsRuntime(cancel: Bool) async throws {
        let observer = FacadeArchiveObserver()
        let fixture = try await ArchiveFacadeFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        let runtime = try await fixture.runtime()
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        let memory = await fixture.governor.usage(.admittedMemoryBytes)
        await observer.arm(after: 0)
        let saving = Task {
            try await fixture.coordinator.saveArchive(
                owner  : owner,
                runtime: runtime
            )
        }
        await observer.wait()
        #expect(FileManager.default.fileExists(atPath: fixture.ownerRoot.path))
        if cancel {
            saving.cancel()
        } else {
            #expect(try await fixture.coordinator.close() == .draining)
        }
        await observer.resume()
        await #expect(throws: (any Error).self) { try await saving.value }
        #expect(await runtime.snapshot(at: fixture.wall).publications.isEmpty)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == memory)
        #expect(try await fixture.coordinator.close() == .closed)
        let retainedMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let retainedDisk = await fixture.governor.usage(.diskBytes)
        try await fixture.coordinator.start()
        let current = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : current,
            runtime: runtime
        ) == .empty)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == retainedMemory)
        #expect(await fixture.governor.usage(.diskBytes) >= retainedDisk)
        await runtime.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

    @Test(arguments: [false, true])
    func knownCommittedSaveSurvivesCoordinatorCloseOrCancellation(cancel: Bool) async throws {
        let observer = FacadeArchiveObserver()
        let fixture = try await ArchiveFacadeFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        let source = try await fixture.runtime()
        _ = try await fixture.publish(source)
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        #expect(try await fixture.coordinator.saveArchive(
            owner  : owner,
            runtime: source
        ).revision == 1)
        let baseline = await fixture.governor.usage(.admittedMemoryBytes)
        // Reused archive.start observes twice; runtime read twice; save observes before commit.
        // The sixth native observation follows the actual SwiftData save. Cancellation must
        // still return revision2, which would fail if this gate preceded the commit boundary.
        await observer.arm(after: 5)
        let saving = Task {
            try await fixture.coordinator.saveArchive(
                owner  : owner,
                runtime: source
            )
        }
        await observer.wait()
        await #expect(throws: AddonStorageCoordinator.Failure.busy) {
            try await fixture.coordinator.readCheckpoint(owner: owner)
        }
        if cancel {
            saving.cancel()
        } else {
            #expect(try await fixture.coordinator.close() == .draining)
        }
        await observer.resume()
        #expect(try await saving.value.revision == 2)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == baseline)
        await source.stop()
        #expect(try await fixture.coordinator.close() == .closed)
        try await fixture.coordinator.start()
        let current = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        let restored = try await fixture.runtime()
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : current,
            runtime: restored
        ) == .restored(
            revision: 2,
            active  : 1,
            terminal: 0
        ))
        await restored.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

    @Test(arguments: [false, true])
    func knownCommittedRestorationSurvivesCoordinatorCloseOrCancellation(cancel: Bool) async throws {
        let fixture = try await ArchiveFacadeFixture.make()
        defer { fixture.removeFiles() }
        let source = try await fixture.runtime()
        let publicationID = try await fixture.publish(source)
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        _ = try await fixture.coordinator.saveArchive(
            owner  : owner,
            runtime: source
        )
        await source.stop()
        let gate = GatedRuntimeResourceAccess(target: fixture.governor)
        let access = FacadeReductionRefusal(gate: gate)
        let target = try await fixture.runtime(access: access)
        let initialPool = try #require(await target.diagnostics(owner: fixture.owner)).reservedStateBytes
        await gate.armResize()
        await access.refuseNextReduction()
        let assignment = Task {
            try await target.assignPublication(
                owner     : fixture.owner,
                featureID : "controls",
                instanceID: UUID()
            )
        }
        await gate.waitForArrival()
        assignment.cancel()
        await gate.releaseGate()
        await #expect(throws: (any Error).self) { try await assignment.value }
        // A deliberate failed refund retains real prepaid slack; no successful allocation is faked.
        #expect(await target.diagnostics(owner: fixture.owner)?.reservedStateBytes == initialPool + 2_048)
        await gate.armReduction()
        let restoring = Task {
            try await fixture.coordinator.restoreArchive(
                owner  : owner,
                runtime: target
            )
        }
        await gate.waitForArrival()
        #expect(await target.snapshot(at: fixture.wall).publications.first?.id == publicationID)
        await #expect(throws: AddonStorageCoordinator.Failure.busy) {
            try await fixture.coordinator.restoreArchive(
                owner  : owner,
                runtime: target
            )
        }
        if cancel {
            restoring.cancel()
        } else {
            #expect(try await fixture.coordinator.close() == .draining)
        }
        await gate.releaseGate()
        #expect(try await restoring.value == .restored(
            revision: 1,
            active  : 1,
            terminal: 0
        ))
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 16_384)
        await target.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

    @Test
    func unreadableOwnerModelDoesNotCloseNormalStorageForAnotherRegisteredOwner() async throws {
        let other = try ActionFixture(ownerName: "com.example.other-retained").context().installed.verifiedIdentity
        let fixture = try await ArchiveFacadeFixture.make(otherIdentity: other)
        defer { fixture.removeFiles() }
        try FileManager.default.createDirectory(
            at                         : fixture.ownerRoot,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let model = fixture.ownerRoot.appendingPathComponent("archive.store")
        try Data([1, 2, 3]).write(to: model)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: model.path
        )
        let runtime = try await fixture.runtime()
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator.restoreArchive(
                owner  : owner,
                runtime: runtime
            )
        }
        let otherOwner = try await fixture.coordinator.owner(for: other)
        try await fixture.coordinator.write(
            Data([8]),
            key  : "safe",
            owner: otherOwner
        )
        #expect(try await fixture.coordinator.read(
            key  : "safe",
            owner: otherOwner
        ) == Data([8]))
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == 32_768)
        await runtime.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

    @Test
    func facadeRoundtripSharesPixelsOnceWithFreshAliasesAndIsolatedAuthority() async throws {
        let fixture = try await ArchiveFacadeFixture.make()
        defer { fixture.removeFiles() }
        let source = try await fixture.runtime()
        let partition = AssetPrivacyPartition.isolated(UUID())
        let saved = try await fixture.publishSharedImages(
            source,
            partition: partition
        )
        let owner = try await fixture.coordinator.owner(for: fixture.installed.verifiedIdentity)
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        // Measure archive and native-slot retention separately from the four real pixel bytes.
        // The fresh runtime must return to the same exact retained footprint after all scratch ends.
        let retainedMemoryWithoutPixels = await fixture.governor.usage(.admittedMemoryBytes) - 4
        _ = try await fixture.coordinator.saveArchive(
            owner  : owner,
            runtime: source
        )
        await source.stop()
        let target = try await fixture.runtime()
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : owner,
            runtime: target
        ) == .restored(
            revision: 1,
            active  : 2,
            terminal: 0
        ))
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == retainedMemoryWithoutPixels + 4)
        let snapshot = await target.snapshot(at: fixture.wall).publications
        let first = try #require(snapshot.first(where: { $0.id == saved.ids[0] }))
        let second = try #require(snapshot.first(where: { $0.id == saved.ids[1] }))
        let firstAlias = try #require(first.content?.minimal?.assets.first)
        let secondAlias = try #require(second.content?.widget?.assets.first)
        #expect(firstAlias != secondAlias)
        #expect(!saved.aliases.contains(firstAlias) && !saved.aliases.contains(secondAlias))
        #expect(first.expiresAt == fixture.wall.addingTimeInterval(8 * 3_600))
        #expect(first.content?.minimal?.privacy == .sensitive)
        let future = await target.snapshot(at: fixture.wall.addingTimeInterval(20)).publications
        #expect(future.first(where: { $0.id == saved.ids[0] })?.content?.minimal?.root.children?.first?.text == "Future")
        var borrowed = await target.assetImage(
            assetID            : firstAlias,
            publicationID      : saved.ids[0],
            publicationRevision: 0
        )
        #expect(borrowed?.dataProvider?.data as Data? == Data([255, 0, 0, 255]))
        #expect(await target.assetImage(
            assetID            : secondAlias,
            publicationID      : saved.ids[1],
            publicationRevision: 0
        ) === borrowed)
        #expect(await target.assetImage(
            assetID            : saved.aliases[0],
            publicationID      : saved.ids[0],
            publicationRevision: 0
        ) == nil)
        #expect(await target.assetImage(
            assetID            : firstAlias,
            publicationID      : saved.ids[1],
            publicationRevision: 0
        ) == nil)
        for stalePartition in [partition, .addonOwned] {
            await #expect(throws: AddonFailure.self) {
                try await target.assignPublication(
                    owner                : fixture.owner,
                    featureID            : "controls",
                    instanceID           : saved.ids[0].instanceID,
                    assetPrivacyPartition: stalePartition
                )
            }
        }
        #expect(try await fixture.coordinator.saveArchive(
            owner  : owner,
            runtime: target
        ).revision == 2)
        await target.stop()
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(borrowed?.width == 1)
        let next = try await fixture.runtime()
        #expect(try await fixture.coordinator.restoreArchive(
            owner  : owner,
            runtime: next
        ) == .restored(
            revision: 2,
            active  : 2,
            terminal: 0
        ))
        #expect(await fixture.governor.usage(.assetBytes) == 8)
        borrowed = nil
        await next.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

}

/// ArchiveFacadeFixture composes real storage and runtime while exposing no raw archive capability.
private struct ArchiveFacadeFixture: Sendable {
    let installed  : InstalledAddon
    let governor   : ResourceGovernor
    let adapter    : RecordingRuntimeAdapter
    let clock      : MutableRuntimeClock
    let coordinator: AddonStorageCoordinator
    let root       : URL
    let archiveRoot: URL
    let wall       : Date
    var owner: AddonID { installed.manifest.id }
    var ownerRoot: URL {
        archiveRoot.appendingPathComponent(KeyedStorageRecord.hex(
            KeyedStorageRecord.namespaceDigest(installed.verifiedIdentity)
        ))
    }

    /// make establishes the real global storage barrier while leaving every archive unopened.
    static func make(
        observer     : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver(),
        otherIdentity: VerifiedAddonIdentity? = nil
    ) async throws -> Self {
        let base = try ActionFixture()
        let installed = try base.context().installed
        let governor = ResourceGovernor()
        let root = URL(fileURLWithPath: "/private/tmp/cascade-archive-facade-\(UUID())")
        let checkpointRoot = root.appendingPathComponent("checkpoints")
        let keyedRoot = root.appendingPathComponent("keyed")
        let archiveRoot = root.appendingPathComponent("archives")
        for directory in [root, checkpointRoot, keyedRoot, archiveRoot] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        var registrations = [StateRegistration(
            identity            : installed.verifiedIdentity,
            maximumSchemaVersion: 1
        )]
        if let otherIdentity {
            registrations.append(StateRegistration(
                identity            : otherIdentity,
                maximumSchemaVersion: 1
            ))
        }
        let coordinator = try await AddonStorageCoordinator.make(
            checkpointRoot : checkpointRoot,
            keyedRoot      : keyedRoot,
            archiveRoot    : archiveRoot,
            registrations  : registrations,
            governor       : governor,
            archiveObserver: observer
        )
        try await coordinator.start()
        return Self(
            installed  : installed,
            governor   : governor,
            adapter    : RecordingRuntimeAdapter(),
            clock      : MutableRuntimeClock(instant: RuntimeInstant(
                wall     : base.wall,
                monotonic: .zero
            )),
            coordinator: coordinator,
            root       : root,
            archiveRoot: archiveRoot,
            wall       : base.wall
        )
    }

    /// runtime creates an independently fresh host lifecycle on the selected real governor.
    func runtime(
        governor : ResourceGovernor? = nil,
        access   : (any RuntimeResourceAccess)? = nil,
        installed: InstalledAddon? = nil
    ) async throws -> AddonRuntime {
        let selectedGovernor = governor ?? self.governor
        let selectedInstalled = installed ?? self.installed
        return try await AddonRuntime.make(
            catalog    : [selectedInstalled],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [selectedInstalled.manifest.id: []],
                explicitBindings: []
            ),
            governor              : selectedGovernor,
            resourceAccess        : access ?? selectedGovernor,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock
        )
    }

    /// publish admits one real full-timeline publication and completes its simulated transport lifetime.
    func publish(_ runtime: AddonRuntime) async throws -> PublicationID {
        let id = try await runtime.assignPublication(
            owner     : owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        func presentation(_ text: String) throws -> PresentationSet {
            try PresentationSet(
                widget: ContentDocument(
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
        let publication = try Publication(
            id         : id,
            revision   : 0,
            kind       : .widget,
            content    : nil,
            timeline   : [
                ScheduledEntry(
                    date   : wall,
                    content: presentation("Now")
                ),
                ScheduledEntry(
                    date   : wall.addingTimeInterval(20),
                    content: presentation("Future")
                )
            ],
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .retainMarked
        )
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : [publication],
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await runtime.observeExit(connection.incarnation)
        return id
    }

    /// publishSharedImages uses actual decode/share admission and retains no native output in the fixture.
    func publishSharedImages(
        _ runtime: AddonRuntime,
        partition: AssetPrivacyPartition
    ) async throws -> (ids: [PublicationID], aliases: [String]) {
        var ids: [PublicationID] = []
        for feature in ["controls", "other"] {
            ids.append(try await runtime.assignPublication(
                owner                : owner,
                featureID            : feature,
                instanceID           : UUID(),
                assetPrivacyPartition: partition
            ))
        }
        let launch = try await runtime.requestLaunch(owner: owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let image = try await runtime.importAsset(
            encoded      : facadePNG(),
            publicationID: ids[0],
            connection   : connection
        )
        let shared = try await runtime.shareAsset(
            assetID   : image.assetID,
            from      : ids[0],
            to        : ids[1],
            connection: connection
        )
        let aliases = [image.assetID, shared.assetID]
        let publications = try ids.indices.map { index in
            func presentation(_ text: String) throws -> PresentationSet {
                let document = try ContentDocument(
                    root: .column([
                        .text(text),
                        ContentNode(
                            kind              : .image,
                            text              : nil,
                            assetID           : aliases[index],
                            value             : nil,
                            deadline          : nil,
                            actionID          : nil,
                            children          : nil,
                            accessibilityLabel: "Red pixel"
                        )
                    ]),
                    privacy           : .sensitive,
                    accessibilityLabel: "Shared image",
                    assetIDs          : [aliases[index]]
                )
                return try PresentationSet(
                    widget         : index == 0 ? nil : document,
                    compactLeading : document,
                    compactTrailing: document,
                    minimal        : document,
                    expanded       : document
                )
            }
            return try Publication(
                id         : ids[index],
                revision   : 0,
                kind       : index == 0 ? .activity : .widget,
                content    : nil,
                timeline   : [
                    ScheduledEntry(
                        date   : wall,
                        content: presentation("Now")
                    ),
                    ScheduledEntry(
                        date   : wall.addingTimeInterval(20),
                        content: presentation("Future")
                    )
                ],
                expiresAt  : wall.addingTimeInterval(8 * 3_600),
                stalePolicy: .retainMarked
            )
        }
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : 1
        )
        await runtime.observeExit(connection.incarnation)
        return (ids, aliases)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

/// FacadeArchiveObserver delays a chosen real observation without omitting measured file bytes.
private actor FacadeArchiveObserver: SwiftDataArchiveObserving {
    private var countdown: Int?
    private var arrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func arm(after count: Int) {
        countdown = count
        arrived = false
    }
    func wait() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resume() {
        completion?.resume()
        completion = nil
    }
    /// inventory measures the real held root before delaying its return at the requested boundary.
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let observed = SwiftDataArchiveDirectory.inventory(
            root      : root,
            descriptor: descriptor
        )
        if let countdown {
            if countdown == 0 {
                self.countdown = nil
                arrived = true
                arrival?.resume()
                arrival = nil
                await withCheckedContinuation { completion = $0 }
            } else {
                self.countdown = countdown - 1
            }
        }
        return observed
    }
}

/// FacadeReductionRefusal injects one failed refund while every successful operation uses the real governor.
private actor FacadeReductionRefusal: RuntimeResourceAccess {
    nonisolated let resourceGovernorTarget: ResourceGovernor
    private let gate: GatedRuntimeResourceAccess
    private var refusesReduction = false

    init(gate: GatedRuntimeResourceAccess) {
        self.gate = gate
        resourceGovernorTarget = gate.resourceGovernorTarget
    }
    func refuseNextReduction() { refusesReduction = true }
    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        try await gate.admit(
            request,
            owner: owner
        )
    }
    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        try await gate.release(
            reservationID,
            owner: owner
        )
    }
    /// reduceStateReservation may refuse one refund; accepted refunds always reach the real governor.
    func reduceStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        toBytes        : Int
    ) async -> Bool {
        if refusesReduction {
            refusesReduction = false
            return false
        }
        return await gate.reduceStateReservation(
            reservationID,
            owner  : owner,
            toBytes: toBytes
        )
    }
    func resizeStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) async throws -> Bool {
        try await gate.resizeStateReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }
    func resizeDiskReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) async throws -> Bool {
        try await gate.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }
}

/// facadePNG encodes one actual red pixel for the canonical runtime importer.
private func facadePNG() throws -> Data {
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
