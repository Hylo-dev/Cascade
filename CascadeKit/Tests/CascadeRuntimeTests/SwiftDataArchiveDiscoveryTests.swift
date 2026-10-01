//
//  SwiftDataArchiveDiscoveryTests.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing

@testable import CascadeRuntime

@Suite
struct SwiftDataArchiveDiscoveryTests {
    private final class Fixture {
        let root: URL
        let identity: VerifiedAddonIdentity
        var descriptor: Int32

        init() throws {
            root = URL(fileURLWithPath: "/private/tmp/cascade-archive-discovery-\(UUID())")
            try FileManager.default.createDirectory(
                at                         : root,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
            identity = VerifiedAddonIdentity(
                publisher: "publisher.discovery",
                addonID  : try #require(AddonID(rawValue: "com.example.discovery"))
            )
            descriptor = try KeyedStorageDirectory.openRoot(root)
        }

        deinit {
            if descriptor >= 0 { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: root)
        }

        func child(_ identity: VerifiedAddonIdentity? = nil) -> URL {
            root.appendingPathComponent(
                KeyedStorageRecord.hex(
                    KeyedStorageRecord.namespaceDigest(identity ?? self.identity)
                )
            )
        }

        func discover(_ governor: ResourceGovernor) async throws -> SwiftDataArchive {
            try await SwiftDataArchive.discover(
                identity        : identity,
                parentRoot      : root,
                parentDescriptor: descriptor,
                governor        : governor
            )
        }
    }

    @Test
    func absentDiscoveryRetainsProtectedMetadataWithoutCreatingFiles() async throws {
        let fixture = try Fixture()
        let governor = ResourceGovernor()
        let archive = try await fixture.discover(governor)
        #expect(await archive.inventoryStatus() == .absent)
        #expect(await archive.status().state == .unavailable)
        #expect(await governor.usage(.diskStateBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 16_384 + 1_024)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
        await governor.releaseAll(owner: fixture.identity.addonID)
        #expect(await governor.usage(.retainedStateBytes) == 16_384 + 1_024)
        #expect(try await archive.reconcile().measuredBytes == 0)
    }

    @Test
    func siblingsRetainSharedParentAfterCallerClosesItsDescriptor() async throws {
        let fixture = try Fixture()
        let governor = ResourceGovernor()
        let first = try await fixture.discover(governor)
        let secondIdentity = VerifiedAddonIdentity(
            publisher: fixture.identity.publisher,
            addonID  : try #require(AddonID(rawValue: "com.example.discovery.second"))
        )
        let second = try await SwiftDataArchive.discover(
            identity        : secondIdentity,
            parentRoot      : fixture.root,
            parentDescriptor: fixture.descriptor,
            governor        : governor
        )
        Darwin.close(fixture.descriptor)
        fixture.descriptor = -1
        #expect(try await first.reconcile().measuredBytes == 0)
        #expect(try await second.reconcile().measuredBytes == 0)
        #expect(await governor.usage(.retainedStateBytes) == 2 * (16_384 + 1_024))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test(arguments: [false, true])
    func provisioningIsStrictAndRetryKeepsOneLedger(allowDirectory: Bool) async throws {
        let fixture = try Fixture()
        let governor = ResourceGovernor()
        let occupied = 10 * 1_024 * 1_024 - (allowDirectory ? 4_096 : 4_095)
        let reservation = try await governor.admit(
            .diskState(bytes: occupied),
            owner: fixture.identity.addonID
        )
        let archive = try await fixture.discover(governor)
        await #expect(throws: AddonFailure.self) { try await archive.start() }
        #expect(FileManager.default.fileExists(atPath: fixture.child().path) == allowDirectory)
        #expect(await governor.usage(.diskStateBytes) == occupied + (allowDirectory ? 4_096 : 0))
        #expect(!FileManager.default.fileExists(atPath: fixture.child().appendingPathComponent("archive.store").path))
        try await governor.release(
            reservation.id,
            owner: fixture.identity.addonID
        )
        #expect(try await archive.start().state == .ready)
        #expect(await archive.inventoryStatus() == .complete)
        #expect(await governor.usage(.retainedStateBytes) == 16_384 + 1_024)
    }

    @Test(arguments: ["throwBefore", "cancelBefore", "cancelAfter", "exists"])
    func provisioningFailuresReconcileRealFilesBeforeRetry(_ point: String) async throws {
        let fixture = try Fixture()
        let governor = ResourceGovernor()
        let creator = ControlledDiscoveryCreation(point: point)
        let archive = try await SwiftDataArchive.discover(
            identity         : fixture.identity,
            parentRoot       : fixture.root,
            parentDescriptor : fixture.descriptor,
            governor         : governor,
            directoryCreation: creator
        )
        let operation = Task { try await archive.start() }
        if point == "exists" {
            #expect(try await operation.value.state == .ready)
        } else {
            do {
                _ = try await operation.value
                Issue.record("Provisioning failure unexpectedly opened the archive")
            } catch {}
            let created = point == "cancelAfter"
            #expect(FileManager.default.fileExists(atPath: fixture.child().path) == created)
            #expect(await governor.usage(.diskStateBytes) == (created ? 4_096 : 0))
            #expect(await archive.inventoryStatus() == (created ? .complete : .absent))
            #expect(
                !FileManager.default.fileExists(atPath: fixture.child().appendingPathComponent("archive.store").path)
            )
            #expect(try await archive.start().state == .ready)
        }
        #expect(await governor.usage(.retainedStateBytes) == 16_384 + 1_024)
    }

    @Test
    func existingDebtAllowsDiscoveryButCannotProvision() async throws {
        let fixture = try Fixture()
        let governor = ResourceGovernor()
        let debt = try await governor.admitObservedDisk(
            bytes: 0,
            owner: fixture.identity.addonID
        )
        #expect(
            try await governor.reconcileObservedDisk(
                debt,
                owner        : fixture.identity.addonID,
                fromBytes    : 0,
                measuredBytes: 10 * 1_024 * 1_024 + 1
            )
        )
        let archive = try await fixture.discover(governor)
        #expect(await archive.inventoryStatus() == .absent)
        await #expect(throws: AddonFailure.self) { try await archive.start() }
        #expect(!FileManager.default.fileExists(atPath: fixture.child().path))
        #expect(await governor.usage(.diskStateBytes) == 10 * 1_024 * 1_024 + 1)
        #expect(
            try await governor.reconcileObservedDisk(
                debt,
                owner        : fixture.identity.addonID,
                fromBytes    : 10 * 1_024 * 1_024 + 1,
                measuredBytes: 0
            )
        )
        try await governor.completeObservedDisk(
            debt,
            owner: fixture.identity.addonID
        )
        #expect(try await archive.start().state == .ready)
    }

    @Test(arguments: ["symlink", "file", "mode", "locked"])
    func unsafeExistingChildStaysOwnedAndBlocksFramework(_ condition: String) async throws {
        let fixture = try Fixture()
        let child = fixture.child()
        var locked: Int32 = -1
        defer { if locked >= 0 { Darwin.close(locked) } }
        switch condition {
        case "symlink":
            try FileManager.default.createSymbolicLink(
                atPath             : child.path,
                withDestinationPath: fixture.root.path
            )
        case "file":
            try Data([1, 2, 3]).write(to: child)
        default:
            try FileManager.default.createDirectory(
                at                         : child,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
            if condition == "mode" {
                #expect(
                    chmod(
                        child.path,
                        0o755
                    ) == 0
                )
            }
            if condition == "locked" { locked = try KeyedStorageDirectory.openRoot(child) }
        }
        let governor = ResourceGovernor()
        let archive = try await fixture.discover(governor)
        #expect(await archive.inventoryStatus() == .blocked)
        #expect(await archive.status().state == .faulted)
        #expect(await governor.usage(.diskStateBytes) >= 4_096)
        if condition == "file" { #expect(await governor.usage(.diskStateBytes) == 4_099) }
        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.start() }
        #expect(await governor.usage(.retainedStateBytes) == 16_384 + 1_024)
        if condition == "mode" {
            #expect(
                chmod(
                    child.path,
                    0o700
                ) == 0
            )
            #expect(try await archive.reconcile().measuredBytes == 4_096)
            #expect(await archive.inventoryStatus() == .complete)
        }
    }

    @Test(arguments: ["child", "missing", "parent"])
    func acquiredDirectoryNeverAdoptsAReplacement(_ condition: String) async throws {
        let fixture = try Fixture()
        try FileManager.default.createDirectory(
            at                         : fixture.child(),
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let file = fixture.child().appendingPathComponent("archive.store")
        try Data(
            repeating: 7,
            count    : 100
        ).write(to: file)
        #expect(
            chmod(
                file.path,
                0o600
            ) == 0
        )
        let governor = ResourceGovernor()
        let archive = try await fixture.discover(governor)
        #expect(await governor.usage(.diskStateBytes) == 8_292)
        let original = condition == "parent" ? fixture.root : fixture.child()
        let parked = URL(fileURLWithPath: original.path + "-held")
        defer {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.moveItem(
                at: parked,
                to: original
            )
        }
        try FileManager.default.moveItem(
            at: original,
            to: parked
        )
        if condition != "missing" {
            try FileManager.default.createDirectory(
                at                         : original,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.reconcile() }
        #expect(await archive.inventoryStatus() == .blocked)
        #expect(await governor.usage(.diskStateBytes) == 8_292)
        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.start() }
        if condition != "missing" {
            #expect(try FileManager.default.contentsOfDirectory(atPath: original.path).isEmpty)
        }
        try? FileManager.default.removeItem(at: original)
        try FileManager.default.moveItem(
            at: parked,
            to: original
        )
        // Only the originally held identity can establish complete inventory and a truthful refund.
        try FileManager.default.removeItem(at: file)
        #expect(try await archive.reconcile().measuredBytes == 4_096)
        #expect(await archive.inventoryStatus() == .complete)
    }

    @Test
    func completedObservationSurvivesParentReplacementBeforeReturn() async throws {
        let fixture = try Fixture()
        let child = fixture.child()
        try FileManager.default.createDirectory(
            at                         : child,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let file = child.appendingPathComponent("archive.store")
        try Data(
            repeating: 7,
            count    : 100
        ).write(to: file)
        #expect(
            chmod(
                file.path,
                0o600
            ) == 0
        )
        let parked = URL(fileURLWithPath: fixture.root.path + "-held")
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.moveItem(
                at: parked,
                to: fixture.root
            )
        }
        let governor = ResourceGovernor()
        let archive = try await SwiftDataArchive.discover(
            identity        : fixture.identity,
            parentRoot      : fixture.root,
            parentDescriptor: fixture.descriptor,
            governor        : governor,
            observer        : MovingDiscoveryObserver(
                parent: fixture.root,
                parked: parked
            )
        )
        #expect(FileManager.default.fileExists(atPath: parked.path))
        #expect(await archive.inventoryStatus() == .blocked)
        // The observer really saw 100 bytes plus two 4KiB entries before the parent changed.
        #expect(await governor.usage(.diskStateBytes) == 8_292)
    }

    @Test
    func cancelledDiscoveryStillReturnsTheAlreadyInventoriedObject() async throws {
        let fixture = try Fixture()
        try FileManager.default.createDirectory(
            at                         : fixture.child(),
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )
        let governor = ResourceGovernor()
        let identity = fixture.identity
        let root = fixture.root
        let descriptor = fixture.descriptor
        let operation = Task {
            try await SwiftDataArchive.discover(
                identity        : identity,
                parentRoot      : root,
                parentDescriptor: descriptor,
                governor        : governor,
                observer        : CancellingDiscoveryObserver()
            )
        }
        let archive = try await operation.value
        #expect(operation.isCancelled)
        #expect(await archive.inventoryStatus() == .complete)
        #expect(await governor.usage(.diskStateBytes) == 4_096)
        #expect(await governor.usage(.retainedStateBytes) == 16_384 + 1_024)
    }

    @Test
    func derivedChildURLIsBoundedBeforeAnyLedgerAdmission() async throws {
        let fixture = try Fixture()
        let governor = ResourceGovernor()
        let oversizedDerivedRoot = try #require(
            URL(
                string: "file:///"
                    + String(
                        repeating: "a",
                        count    : 4_050
                    )
            )
        )
        #expect(oversizedDerivedRoot.absoluteString.utf8.count < 4_096)
        await #expect(throws: SwiftDataArchiveFailure.invalidConfiguration) {
            try await SwiftDataArchive.discover(
                identity        : fixture.identity,
                parentRoot      : oversizedDerivedRoot,
                parentDescriptor: fixture.descriptor,
                governor        : governor
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(await governor.usage(.diskStateBytes) == 0)
    }

}
