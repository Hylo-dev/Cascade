//
//  AddonStorageArchiveInventoryTests.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonStorageArchiveInventoryTests {
    @Test
    func absentOwnersAreInventoriedBeforeReadinessWithoutCreatingArchives() async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        let initialState = await governor.usage(.retainedStateBytes)
        try await coordinator.start()
        for identity in fixture.identities {
            _ = try await coordinator.owner(for: identity)
        }
        #expect(try fixture.names(in: fixture.archiveRoot).isEmpty)
        // Two checkpoint namespaces, keyed root, and the independently owned archive root.
        #expect(await governor.usage(.diskBytes) == 4 * 4_096)
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.diskBytes) == 2 * 4_096)
        #expect(await governor.usage(.retainedStateBytes) >= initialState + 2 * 17_408)
        #expect(await governor.usage(.admittedMemoryBytes) == 2 * 16_384)
    }

    @Test
    func unknownOuterEntryBlocksAllAccessBeforeCheckpointRecovery() async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let unexpected = fixture.archiveRoot.appendingPathComponent("unknown-owner")
        try Data([5]).write(to: unexpected)
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        for identity in fixture.identities {
            await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
                try await coordinator.owner(for: identity)
            }
        }
        #expect(try fixture.names(in: fixture.checkpointRoot).isEmpty)
        #expect(try fixture.names(in: fixture.keyedRoot).isEmpty)
        #expect(await governor.usage(.diskBytes) == 4_096)
        #expect(await governor.usage(.admittedMemoryBytes) == 2 * 16_384)
        let retainedState = await governor.usage(.retainedStateBytes)
        try FileManager.default.removeItem(at: unexpected)
        try await coordinator.start()
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.retainedStateBytes) > retainedState)
        #expect(try fixture.names(in: fixture.archiveRoot).isEmpty)
    }
    @Test(arguments: ["unsafe", "unknown", "incomplete"])
    func aFaultedKnownOwnerCannotHideLaterOwners(fault: String) async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let first = try fixture.createOwner(index: 0)
        let second = try fixture.createOwner(index: 1)
        let observer = ArchiveInventoryObserver()
        var extra: URL?
        if fault == "unsafe" {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: first.path
            )
        } else if fault == "unknown" {
            let file = first.appendingPathComponent("unrecognized")
            try fixture.writePrivate(
                Data([4]),
                to: file
            )
            extra = file
        } else {
            await observer.markIncomplete(first.lastPathComponent)
        }
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(
            governor: governor,
            observer: observer
        )
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        #expect(try fixture.names(in: fixture.checkpointRoot).isEmpty)
        #expect(try fixture.names(in: fixture.keyedRoot).isEmpty)
        #expect(await observer.count(second.lastPathComponent) == 1)
        #expect(await governor.usage(.admittedMemoryBytes) == 32_768)
        #expect(await governor.usage(
            .diskBytes,
            owner: fixture.identities[1].addonID
        ) == 4_096)
        let stateBefore = await governor.usage(.retainedStateBytes)
        if let extra { try FileManager.default.removeItem(at: extra) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: first.path
        )
        await observer.markIncomplete(nil)
        try await coordinator.start()
        let firstOwner = try await coordinator.owner(for: fixture.identities[0])
        #expect(try await coordinator.readCheckpoint(owner: firstOwner) == nil)
        #expect(try await coordinator.close() == .closed)
        let closedState = await governor.usage(.retainedStateBytes)
        #expect(closedState > stateBefore)
        let closedDisk = await governor.usage(.diskBytes)
        for _ in 0..<3 {
            try await coordinator.start()
            let current = try await coordinator.owner(for: fixture.identities[0])
            #expect(current != firstOwner)
            await #expect(throws: AddonStorageCoordinator.Failure.invalidOwner) {
                try await coordinator.readCheckpoint(owner: firstOwner)
            }
            #expect(try await coordinator.readCheckpoint(owner: current) == nil)
            #expect(try await coordinator.close() == .closed)
            #expect(await governor.usage(.retainedStateBytes) == closedState)
            #expect(await governor.usage(.diskBytes) == closedDisk)
        }
        #expect(try fixture.names(in: first).isEmpty)
        #expect(try fixture.names(in: second).isEmpty)
    }

    @Test(arguments: [false, true])
    func interruptedDiscoveryRetainsReturnedOwnerBeforeRejectingStartup(cancel: Bool) async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let first = try fixture.createOwner(index: 0)
        _ = try fixture.createOwner(index: 1)
        try fixture.writePrivate(
            Data([1, 2, 3]),
            to: first.appendingPathComponent("archive.store")
        )
        let observer = ArchiveInventoryObserver()
        await observer.arm(first.lastPathComponent)
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(
            governor: governor,
            observer: observer
        )
        let starting = Task { try await coordinator.start() }
        await observer.wait()
        #expect(await governor.usage(.diskBytes) == 4_096)
        #expect(try fixture.names(in: fixture.checkpointRoot).isEmpty)
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) {
            try await coordinator.owner(for: fixture.identities[0])
        }
        if cancel {
            starting.cancel()
        } else {
            #expect(try await coordinator.close() == .draining)
        }
        await observer.resume()
        await #expect(throws: (any Error).self) { try await starting.value }
        #expect(await governor.usage(.diskBytes) == 12_291)
        #expect(await governor.usage(.admittedMemoryBytes) == 16_384)
        #expect(try await coordinator.close() == .closed)
        try await coordinator.start()
        #expect(await governor.usage(.admittedMemoryBytes) == 32_768)
        #expect(await observer.count(first.lastPathComponent) == 2)
        // Raw malformed bytes remain unopened and do not prevent normal storage readiness.
        #expect(try Data(contentsOf: first.appendingPathComponent("archive.store")) == Data([1, 2, 3]))
        #expect(try fixture.names(in: first) == ["archive.store"])
        #expect(try await coordinator.close() == .closed)
    }

    @Test(arguments: ["missing", "mode", "symlink"])
    func unsafeOuterRootNeverCreatesChildrenOrOpensBackends(problem: String) async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let moved = fixture.root.appendingPathComponent("held-elsewhere")
        if problem == "mode" {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fixture.archiveRoot.path
            )
        } else {
            try FileManager.default.moveItem(
                at: fixture.archiveRoot,
                to: moved
            )
            if problem == "symlink" {
                try FileManager.default.createSymbolicLink(
                    at                : fixture.archiveRoot,
                    withDestinationURL: moved
                )
            }
        }
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        let stateBefore = await governor.usage(.retainedStateBytes)
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        #expect(await governor.usage(.diskBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == stateBefore)
        #expect(try fixture.names(in: fixture.checkpointRoot).isEmpty)
        #expect(try fixture.names(in: fixture.keyedRoot).isEmpty)
        if problem == "mode" {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fixture.archiveRoot.path
            )
        } else {
            if problem == "symlink" { try FileManager.default.removeItem(at: fixture.archiveRoot) }
            try FileManager.default.moveItem(
                at: moved,
                to: fixture.archiveRoot
            )
        }
        try await coordinator.start()
        #expect(try await coordinator.close() == .closed)
    }

    @Test(arguments: [false, true])
    func retainedParentAndChildCannotBeReplacedOnRestart(replaceParent: Bool) async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let child = try fixture.createOwner(index: 0)
        _ = try fixture.createOwner(index: 1)
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        try await coordinator.start()
        #expect(try await coordinator.close() == .closed)
        let diskBefore = await governor.usage(.diskBytes)
        let stateBefore = await governor.usage(.retainedStateBytes)
        let original = replaceParent ? fixture.archiveRoot : child
        let moved = fixture.root.appendingPathComponent("original-identity")
        try FileManager.default.moveItem(
            at: original,
            to: moved
        )
        try fixture.createDirectory(original)
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        #expect(await governor.usage(.diskBytes) == diskBefore)
        #expect(await governor.usage(.retainedStateBytes) == stateBefore)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.moveItem(
            at: moved,
            to: original
        )
        try await coordinator.start()
        #expect(try await coordinator.close() == .closed)
        #expect(await governor.usage(.diskBytes) == diskBefore)
        #expect(await governor.usage(.retainedStateBytes) == stateBefore)
    }

    @Test
    func protectedRootAndOwnerLedgersSurviveGenericOwnerCleanup() async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let first = try fixture.createOwner(index: 0)
        _ = try fixture.createOwner(index: 1)
        let unknown = fixture.archiveRoot.appendingPathComponent("unknown")
        try fixture.writePrivate(
            Data([0]),
            to: unknown
        )
        try fixture.writePrivate(
            Data([1]),
            to: first.appendingPathComponent("archive.store")
        )
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(governor: governor)
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        let diskBefore = await governor.usage(.diskBytes)
        #expect(diskBefore == 16_385)
        for identity in fixture.identities {
            await governor.releaseAll(owner: identity.addonID)
        }
        #expect(await governor.usage(.diskBytes) == diskBefore)
        // Only protected root token plus both archive token/lifetime charges survive. Existing
        // ordinary coordinator metadata is intentionally not claimed protected by releaseAll.
        #expect(await governor.usage(.retainedStateBytes) == 1_024 + 2 * 17_408)
        #expect(await governor.usage(.admittedMemoryBytes) == 32_768)
        #expect(try await coordinator.close() == .closed)
    }

    @Test
    func priorDiskDebtStillAllowsCompleteDiscoveryBeforeStrictBackendDenial() async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let first = try fixture.createOwner(index: 0)
        let second = try fixture.createOwner(index: 1)
        let governor = ResourceGovernor()
        let debtor = fixture.identities[0].addonID
        let debt = try await governor.admitObservedDisk(
            bytes: 0,
            owner: debtor
        )
        let debtBytes = 10 * 1_024 * 1_024 + 1
        #expect(try await governor.reconcileObservedDisk(
            debt,
            owner        : debtor,
            fromBytes    : 0,
            measuredBytes: debtBytes
        ))
        let observer = ArchiveInventoryObserver()
        let coordinator = try await fixture.make(
            governor: governor,
            observer: observer
        )
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        #expect(await observer.count(first.lastPathComponent) == 1)
        #expect(await observer.count(second.lastPathComponent) == 1)
        #expect(await governor.usage(.diskBytes) == debtBytes + 3 * 4_096)
        #expect(await governor.usage(.admittedMemoryBytes) == 32_768)
        #expect(try fixture.names(in: first).isEmpty)
        #expect(try fixture.names(in: second).isEmpty)
        #expect(try await governor.reconcileObservedDisk(
            debt,
            owner        : debtor,
            fromBytes    : debtBytes,
            measuredBytes: 0
        ))
        try await governor.completeObservedDisk(
            debt,
            owner: debtor
        )
        try await coordinator.start()
        #expect(try await coordinator.close() == .closed)
    }

    @Test(arguments: ["overlong", "overflow"])
    func boundedOuterEnumerationStillDiscoversEveryKnownOwner(boundary: String) async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let first = try fixture.createOwner(index: 0)
        let second = try fixture.createOwner(index: 1)
        let count = boundary == "overflow" ? 257 : 1
        for index in 0..<count {
            let name = boundary == "overlong"
                ? String(
                    repeating: "x",
                    count    : 65
                )
                : "unknown-\(index)"
            try fixture.writePrivate(
                Data([0]),
                to: fixture.archiveRoot.appendingPathComponent(name)
            )
        }
        let observer = ArchiveInventoryObserver()
        let governor = ResourceGovernor()
        let coordinator = try await fixture.make(
            governor: governor,
            observer: observer
        )
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        #expect(await observer.count(first.lastPathComponent) == 1)
        #expect(await observer.count(second.lastPathComponent) == 1)
        #expect(await governor.usage(.diskBytes) == 3 * 4_096)
        #expect(try fixture.names(in: fixture.checkpointRoot).isEmpty)
        #expect(try fixture.names(in: fixture.keyedRoot).isEmpty)
    }

    @Test
    func derivedChildURLIsBoundedBeforeCoordinatorOrTokenAdmission() async throws {
        let fixture = try ArchiveInventoryFixture()
        defer { fixture.removeFiles() }
        let root = URL(fileURLWithPath: "/private/tmp/" + String(
            repeating: "x",
            count    : 4_030
        ))
        let name = KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(fixture.identities[0]))
        #expect(root.absoluteString.utf8.count <= 4_096)
        #expect(root.appendingPathComponent(name).absoluteString.utf8.count > 4_096)
        let governor = ResourceGovernor()
        await #expect(throws: AddonStorageCoordinator.Failure.invalidConfiguration) {
            try await AddonStorageCoordinator.make(
                checkpointRoot: fixture.checkpointRoot,
                keyedRoot     : fixture.keyedRoot,
                archiveRoot   : root,
                registrations : fixture.registrations,
                governor      : governor
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(await governor.usage(.diskBytes) == 0)
    }

}
