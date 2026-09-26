//
//  AddonStorageCoordinatorTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonStorageCoordinatorTests {
    private struct Fixture {
        let root          : URL
        let checkpointRoot: URL
        let keyedRoot     : URL
        let archiveRoot   : URL
        let identity      : VerifiedAddonIdentity
        let registrations : [StateRegistration]

        init() throws {
            root = URL(fileURLWithPath: "/private/tmp/cascade-storage-coordinator-\(UUID())")
            checkpointRoot = root.appendingPathComponent("checkpoints")
            keyedRoot = root.appendingPathComponent("keyed")
            archiveRoot = root.appendingPathComponent("archives")
            for directory in [root, checkpointRoot, keyedRoot, archiveRoot] {
                try FileManager.default.createDirectory(
                    at                         : directory,
                    withIntermediateDirectories: false,
                    attributes                 : [.posixPermissions: 0o700]
                )
            }
            identity = VerifiedAddonIdentity(
                publisher: "publisher.retained",
                addonID  : try #require(AddonID(rawValue: "com.example.storage-barrier"))
            )
            registrations = [StateRegistration(
                identity            : identity,
                maximumSchemaVersion: 2
            )]
        }

        func make(
            governor: ResourceGovernor,
            access  : (any RuntimeResourceAccess)? = nil
        ) async throws -> AddonStorageCoordinator {
            try await AddonStorageCoordinator.make(
                checkpointRoot: checkpointRoot,
                keyedRoot     : keyedRoot,
                archiveRoot   : archiveRoot,
                registrations : registrations,
                governor      : governor,
                resourceAccess: access
            )
        }

        func removeFiles() throws { try FileManager.default.removeItem(at: root) }
    }

    @Test
    func secondRootFailureKeepsCheckpointDataUnavailableUntilRepair() async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let seeded = try await AddonStateStore.open(
            root         : fixture.checkpointRoot,
            registrations: fixture.registrations,
            governor     : ResourceGovernor()
        )
        let seededOwner = try await seeded.owner(for: fixture.identity)
        try await seeded.write(
            Data([7, 8, 9]),
            schemaVersion: 2,
            owner        : seededOwner
        )
        try await seeded.close()
        let unexpected = fixture.keyedRoot.appendingPathComponent("unexpected")
        try Data([42]).write(to: unexpected)
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        let fixedMetadata = await governor.usage(.retainedStateBytes)
        #expect(fixedMetadata > 0)
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.owner(for: fixture.identity)
        }
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.owner(for: fixture.identity)
        }
        #expect(await governor.usage(.diskBytes) == 4_096)
        #expect(await governor.usage(.retainedStateBytes) == fixedMetadata + 17_408)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.checkpointRoot.path).count == 1)
        #expect(try Data(contentsOf: unexpected) == Data([42]))
        try FileManager.default.removeItem(at: unexpected)
        try await coordinator.start()
        let owner = try await coordinator.owner(for: fixture.identity)
        #expect(try await coordinator.readCheckpoint(owner: owner)?.data == Data([7, 8, 9]))
        #expect(try await coordinator.read(
            key  : "missing",
            owner: owner
        ) == nil)
        #expect(try await coordinator.close() == .closed)
    }

    @Test
    func fixedRegistryMetadataIsPrepaidAndInvalidRegistriesNeverOpenRoots() async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let governor = ResourceGovernor()
        let invalidRegistries = [
            [],
            fixture.registrations + fixture.registrations,
            Array(
                repeating: fixture.registrations[0],
                count    : 257
            ),
            [StateRegistration(
                identity            : fixture.identity,
                maximumSchemaVersion: 0
            )],
            [StateRegistration(
                identity: VerifiedAddonIdentity(
                    publisher: "",
                    addonID  : fixture.identity.addonID
                ),
                maximumSchemaVersion: 1
            )]
        ]
        for registrations in invalidRegistries {
            await #expect(throws: AddonStorageCoordinator.Failure.invalidConfiguration) {
                try await AddonStorageCoordinator.make(
                    checkpointRoot: fixture.checkpointRoot,
                    keyedRoot     : fixture.keyedRoot,
                    archiveRoot   : fixture.archiveRoot,
                    registrations : registrations,
                    governor      : governor
                )
            }
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        let denied = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 0))
        await #expect(throws: AddonFailure.self) {
            try await fixture.make(governor: denied)
        }
        #expect(await denied.usage(.retainedStateBytes) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.checkpointRoot.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.keyedRoot.path).isEmpty)
        let coordinator = try await fixture.make(governor: governor)
        let metadata = await governor.usage(.retainedStateBytes)
        #expect(metadata > 0)
        #expect(await governor.usage(.diskBytes) == 0)
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.retainedStateBytes) == metadata)
    }

    @Test(arguments: ["checkpoint", "keyed", "archive"])
    func rootURLRetentionMustFitPrepaidMetadataBound(selectedRoot: String) async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let governor = ResourceGovernor()
        var query = try #require(URLComponents(
            url                    : fixture.checkpointRoot,
            resolvingAgainstBaseURL: false
        ))
        query.query = String(
            repeating: "q",
            count    : 32_768
        )
        var fragment = query
        fragment.query = nil
        fragment.fragment = String(
            repeating: "f",
            count    : 32_768
        )
        let relative = try #require(URL(
            string    : "child",
            relativeTo: fixture.checkpointRoot
        ))
        let encodedPath = URL(fileURLWithPath: "/private/tmp/" + String(
            repeating: " ",
            count    : 2_000
        ))
        let roots = [try #require(query.url), try #require(fragment.url), relative, encodedPath]
        for root in roots {
            #expect(root.path.utf8.count <= 4_096)
            await #expect(throws: AddonStorageCoordinator.Failure.invalidConfiguration) {
                try await AddonStorageCoordinator.make(
                    checkpointRoot: selectedRoot == "checkpoint" ? root : fixture.checkpointRoot,
                    keyedRoot     : selectedRoot == "keyed" ? root : fixture.keyedRoot,
                    archiveRoot   : selectedRoot == "archive" ? root : fixture.archiveRoot,
                    registrations : fixture.registrations,
                    governor      : governor
                )
            }
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(await governor.usage(.diskBytes) == 0)
    }

    @Test
    func retainedKeyedLedgerAndCommittedValuesSurviveRepeatedCloseAndRepair() async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        try await coordinator.start()
        let originalOwner = try await coordinator.owner(for: fixture.identity)
        try await coordinator.writeCheckpoint(
            Data([1, 2]),
            schemaVersion: 1,
            owner        : originalOwner
        )
        try await coordinator.write(
            Data([3, 4]),
            key  : "preferences",
            owner: originalOwner
        )
        try await coordinator.write(
            Data([5]),
            key         : "cached",
            owner       : originalOwner,
            storageClass: .cache
        )
        let readyDisk = await governor.usage(.diskBytes)
        let readyMetadata = await governor.usage(.retainedStateBytes)
        #expect(try await coordinator.close() == .closed)
        let closedDisk = await governor.usage(.diskBytes)
        let closedMetadata = await governor.usage(.retainedStateBytes)
        #expect(closedDisk > 0 && closedDisk < readyDisk)
        #expect(closedMetadata > 0 && closedMetadata < readyMetadata)
        let unexpected = fixture.keyedRoot.appendingPathComponent("unexpected")
        try Data([9]).write(to: unexpected)
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        #expect(await governor.usage(.diskBytes) == closedDisk)
        #expect(await governor.usage(.retainedStateBytes) == closedMetadata)
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.readCheckpoint(owner: originalOwner)
        }
        try FileManager.default.removeItem(at: unexpected)
        for _ in 0..<3 {
            try await coordinator.start()
            #expect(await governor.usage(.diskBytes) == readyDisk)
            #expect(await governor.usage(.retainedStateBytes) == readyMetadata)
            let currentOwner = try await coordinator.owner(for: fixture.identity)
            #expect(currentOwner != originalOwner)
            await #expect(throws: AddonStorageCoordinator.Failure.invalidOwner) {
                try await coordinator.read(
                    key  : "preferences",
                    owner: originalOwner
                )
            }
            #expect(try await coordinator.readCheckpoint(owner: currentOwner)?.data == Data([1, 2]))
            #expect(try await coordinator.read(
                key  : "preferences",
                owner: currentOwner
            ) == Data([3, 4]))
            #expect(try await coordinator.read(
                key         : "cached",
                owner       : currentOwner,
                storageClass: .cache
            ) == Data([5]))
            #expect(try await coordinator.close() == .closed)
            #expect(await governor.usage(.diskBytes) == closedDisk)
            #expect(await governor.usage(.retainedStateBytes) == closedMetadata)
        }
        try await coordinator.start()
        let currentOwner = try await coordinator.owner(for: fixture.identity)
        try await coordinator.remove(
            key  : "preferences",
            owner: currentOwner
        )
        #expect(try await coordinator.read(
            key  : "preferences",
            owner: currentOwner
        ) == nil)
        #expect(try await coordinator.read(
            key         : "cached",
            owner       : currentOwner,
            storageClass: .cache
        ) == Data([5]))
        #expect(try await coordinator.close() == .closed)
    }

    @Test(arguments: [false, true])
    func suspendedStartupPublishesNoOwnerAndCloseOrCancellationCannotReviveIt(cancel: Bool) async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let governor = ResourceGovernor()
        let gate = CoordinatorResourceGate(governor)
        let coordinator = try await fixture.make(
            governor: governor,
            access  : gate
        )
        await gate.arm(.stateAdmission)
        let startup = Task { try await coordinator.start() }
        await gate.wait()
        // Archive root and checkpoint namespace reconcile before keyed metadata admission.
        #expect(await governor.usage(.diskBytes) == 8_192)
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.owner(for: fixture.identity)
        }
        await #expect(throws: AddonStorageCoordinator.Failure.busy) { try await coordinator.start() }
        if cancel {
            startup.cancel()
        } else {
            #expect(try await coordinator.close() == .draining)
        }
        await gate.resume()
        await #expect(throws: (any Error).self) { try await startup.value }
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.owner(for: fixture.identity)
        }
        #expect(await governor.usage(.admittedMemoryBytes) == 16_384)
        // Close after successful keyed open retains its root ledger; cancellation inside the
        // initial backend admission has no established keyed ledger to retain yet.
        #expect(await governor.usage(.diskBytes) == 4_096 + (cancel ? 0 : 4_096))
        #expect(try await coordinator.close() == .closed)
        try await coordinator.start()
        #expect(await governor.usage(.diskBytes) == 12_288)
        let owner = try await coordinator.owner(for: fixture.identity)
        #expect(try await coordinator.readCheckpoint(owner: owner) == nil)
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.diskBytes) == 8_192)
    }

    @Test
    func closeDrainsAcceptedWorkAndRejectsCompetingOperationsAndStaleResults() async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let governor = ResourceGovernor()
        let gate = CoordinatorResourceGate(governor)
        let coordinator = try await fixture.make(
            governor: governor,
            access  : gate
        )
        try await coordinator.start()
        let owner = try await coordinator.owner(for: fixture.identity)
        try await coordinator.write(
            Data([11]),
            key  : "value",
            owner: owner
        )
        await gate.arm(.temporaryAdmission)
        let reading = Task {
            try await coordinator.read(
                key  : "value",
                owner: owner
            )
        }
        await gate.wait()
        await #expect(throws: AddonStorageCoordinator.Failure.busy) {
            try await coordinator.writeCheckpoint(
                Data([8]),
                schemaVersion: 1,
                owner        : owner
            )
        }
        await #expect(throws: AddonStorageCoordinator.Failure.busy) {
            try await coordinator.owner(for: fixture.identity)
        }
        #expect(try await coordinator.close() == .draining)
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.readCheckpoint(owner: owner)
        }
        await gate.resume()
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) { try await reading.value }
        #expect(await governor.usage(.admittedMemoryBytes) == 16_384)
        #expect(try await coordinator.close() == .closed)
        try await coordinator.start()
        let current = try await coordinator.owner(for: fixture.identity)
        #expect(try await coordinator.read(
            key  : "value",
            owner: current
        ) == Data([11]))
        await #expect(throws: AddonStorageCoordinator.Failure.invalidOwner) {
            try await coordinator.write(
                Data([22]),
                key  : "value",
                owner: owner
            )
        }
        #expect(try await coordinator.close() == .closed)
    }

    @Test
    func commonDiskQuotaAndUnrelatedReservationsRemainAuthoritativeAcrossClose() async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        try await coordinator.start()
        let owner = try await coordinator.owner(for: fixture.identity)
        let diskLimit = 10 * 1_024 * 1_024
        let readyDisk = await governor.usage(.diskStateBytes)
        #expect(readyDisk == 12_288)
        let unrelated = try await governor.admit(
            .diskState(bytes: diskLimit - readyDisk),
            owner: fixture.identity.addonID
        )
        await #expect(throws: (any Error).self) {
            try await coordinator.writeCheckpoint(
                Data([1]),
                schemaVersion: 1,
                owner        : owner
            )
        }
        await #expect(throws: (any Error).self) {
            try await coordinator.write(
                Data([2]),
                key  : "denied",
                owner: owner
            )
        }
        #expect(await governor.usage(.diskStateBytes) == diskLimit)
        #expect(try await coordinator.readCheckpoint(owner: owner) == nil)
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.diskStateBytes) == diskLimit - 4_096)
        try await governor.release(
            unrelated.id,
            owner: unrelated.owner
        )
        #expect(await governor.usage(.diskStateBytes) == readyDisk - 4_096)
        try await coordinator.start()
        let current = try await coordinator.owner(for: fixture.identity)
        try await coordinator.write(
            Data([3]),
            key  : "allowed",
            owner: current
        )
        #expect(try await coordinator.close() == .closed)
    }

    @Test
    func ownerCapabilitiesAreBoundToOneCoordinatorAndFixedRegistry() async throws {
        let first = try Fixture()
        let second = try Fixture()
        defer {
            try? first.removeFiles()
            try? second.removeFiles()
        }
        let firstCoordinator = try await first.make(governor: ResourceGovernor())
        let secondCoordinator = try await second.make(governor: ResourceGovernor())
        try await firstCoordinator.start()
        try await secondCoordinator.start()
        let firstOwner = try await firstCoordinator.owner(for: first.identity)
        await #expect(throws: AddonStorageCoordinator.Failure.invalidOwner) {
            try await secondCoordinator.readCheckpoint(owner: firstOwner)
        }
        let foreign = VerifiedAddonIdentity(
            publisher: "foreign.publisher",
            addonID  : first.identity.addonID
        )
        await #expect(throws: AddonStorageCoordinator.Failure.invalidOwner) {
            try await firstCoordinator.owner(for: foreign)
        }
        #expect(try await firstCoordinator.close() == .closed)
        #expect(try await secondCoordinator.close() == .closed)
    }

    @Test(arguments: ["unknown", "symlink", "file", "mode"])
    func lateOuterInventoryChangeCannotPublishReadinessAfterBackendAwait(change: String) async throws {
        let fixture = try Fixture()
        defer { try? fixture.removeFiles() }
        let name = KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(fixture.identity))
        let archiveRoot = fixture.archiveRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at                         : archiveRoot,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let originalBytes = Data([1, 2, 3])
        let model = archiveRoot.appendingPathComponent("archive.store")
        try originalBytes.write(to: model)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: model.path
        )
        let governor = ResourceGovernor()
        let gate = CoordinatorResourceGate(governor)
        let coordinator = try await fixture.make(
            governor: governor,
            access  : gate
        )
        await gate.arm(.stateAdmission)
        let starting = Task { try await coordinator.start() }
        await gate.wait()
        // Root + owner directory + model entry/bytes are already inventoried; checkpoint owns
        // another4KiB here. After failure that checkpoint is refunded and keyed root retained.
        let inventoriedDisk = await governor.usage(.diskBytes)
        #expect(inventoriedDisk == 4 * 4_096 + originalBytes.count)
        let moved = fixture.root.appendingPathComponent("original-archive")
        let unexpected = fixture.archiveRoot.appendingPathComponent("late-unknown")
        if change == "unknown" {
            try Data([3]).write(to: unexpected)
        } else {
            try FileManager.default.moveItem(
                at: archiveRoot,
                to: moved
            )
            switch change {
            case "symlink":
                try FileManager.default.createSymbolicLink(
                    at                : archiveRoot,
                    withDestinationURL: moved
                )
            case "file":
                try Data([4]).write(to: archiveRoot)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: archiveRoot.path
                )
            default:
                try FileManager.default.createDirectory(
                    at                         : archiveRoot,
                    withIntermediateDirectories: false,
                    attributes                 : [.posixPermissions: 0o755]
                )
            }
        }
        await gate.resume()
        await #expect(throws: (any Error).self) { try await starting.value }
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.owner(for: fixture.identity)
        }
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.diskBytes) == inventoriedDisk)
        let retainedMetadata = await governor.usage(.retainedStateBytes)
        if change == "unknown" {
            try FileManager.default.removeItem(at: unexpected)
        } else {
            try FileManager.default.removeItem(at: archiveRoot)
            try FileManager.default.moveItem(
                at: moved,
                to: archiveRoot
            )
        }
        #expect(try Data(contentsOf: model) == originalBytes)
        try await coordinator.start()
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.diskBytes) == inventoriedDisk)
        #expect(await governor.usage(.retainedStateBytes) == retainedMetadata)
    }

}


/// CoordinatorResourceGate delays one real governor result to exercise coordinator reentrancy.
private actor CoordinatorResourceGate: RuntimeResourceAccess {
    enum Point {
        case stateAdmission
        case temporaryAdmission
    }

    nonisolated let resourceGovernorTarget: ResourceGovernor
    private var point     : Point?
    private var hasArrived = false
    private var arrival   : CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    init(_ governor: ResourceGovernor) { resourceGovernorTarget = governor }

    func arm(_ point: Point) {
        self.point = point
        hasArrived = false
    }

    func wait() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func resume() {
        completion?.resume()
        completion = nil
    }

    private func hold(_ candidate: Point) async {
        guard point == candidate else { return }
        point = nil
        hasArrived = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { completion = $0 }
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let reservation = try await resourceGovernorTarget.admit(
            request,
            owner: owner
        )
        switch request {
        case .state:
            await hold(.stateAdmission)
        case .temporaryMemory:
            await hold(.temporaryAdmission)
        default:
            break
        }
        return reservation
    }

    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(
            reservationID,
            owner: owner
        )
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        toBytes        : Int
    ) async -> Bool {
        await resourceGovernorTarget.reduceStateReservation(
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
        try await resourceGovernorTarget.resizeStateReservation(
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
        try await resourceGovernorTarget.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }
}
