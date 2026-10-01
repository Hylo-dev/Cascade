//
//  SwiftDataArchiveTests.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import SwiftData
import Testing
@testable import CascadeRuntime

@Suite
struct SwiftDataArchiveTests {

    private struct Fixture {

        let root    : URL
        let identity: VerifiedAddonIdentity

        init() throws {
            root = URL(fileURLWithPath: "/private/tmp/cascade-swiftdata-backend-\(UUID())")
            try FileManager.default.createDirectory(
                at                         : root,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )

            identity = VerifiedAddonIdentity(
                publisher: "publisher.archive",
                addonID  : try #require(AddonID(rawValue: "com.example.archive"))
            )
        }

        func make(_ governor: ResourceGovernor) async throws -> SwiftDataArchive {
            try await SwiftDataArchive.make(
                identity: identity,
                root    : root,
                governor: governor
            )
        }

        func generation(_ revision: UInt64) -> SwiftDataArchiveGeneration {
            SwiftDataArchiveGeneration(
                schemaVersion : 1,
                revision      : revision,
                verifiedDigest: "verified-digest",
                payload       : Data([1, 3, 5, 7])
            )
        }

        func removeFiles() { try? FileManager.default.removeItem(at: root) }
    }

    @Test
    func savesAndReadsThroughFreshOperationContextsAndLogicalResume() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)

        #expect(await archive.status().state == .unavailable)
        #expect(try await archive.start().state == .ready)

        let generation = fixture.generation(1)
        let result     = try await archive.save(generation, replacing: nil)

        #expect(result.revision == 1)
        #expect(result.status.state == .ready)
        #expect(try await archive.withGeneration { value in value == generation })
        #expect(await archive.suspend().state == .suspended)
        #expect(try await archive.start().state == .ready)
        #expect(try await archive.withGeneration { value in value == generation })
        #expect(await governor.usage(.diskStateBytes) > 4_096)
    }

    @Test
    func rejectsStaleReplacementWithoutChangingCommittedGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let archive  = try await fixture.make(ResourceGovernor())
        _            = try await archive.start()
        let original = fixture.generation(1)
        _            = try await archive.save(original, replacing: nil)

        await #expect(throws: SwiftDataArchiveFailure.self) {
            try await archive.save(fixture.generation(2), replacing: 9)
        }

        #expect(try await archive.withGeneration { value in value == original })
    }

    @Test
    func initialUnknownFileIsChargedAndBlocksFrameworkOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let unknown      = fixture.root.appendingPathComponent("unrecognized")
        let unknownBytes = Data(repeating: 9, count: 7)

        try unknownBytes.write(to: unknown)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: unknown.path
        )

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)

        #expect(await archive.status().state == .faulted)
        #expect(await archive.inventoryStatus() == .blocked)
        #expect(await governor.usage(.diskStateBytes) == 8_199)

        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.start() }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("archive.store").path))
    }

    @Test
    func rollbackAfterModelMutationPreservesThePriorGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let check    = FailingArchiveCommitCheck()
        let governor = ResourceGovernor()
        let archive  = try await SwiftDataArchive.make(
            identity   : fixture.identity,
            root       : fixture.root,
            governor   : governor,
            commitCheck: check
        )

        _            = try await archive.start()
        let original = fixture.generation(1)
        _            = try await archive.save(original, replacing: nil)

        check.failNextCommit()
        await #expect(throws: FailingArchiveCommitCheck.Failure.self) {
            try await archive.save(fixture.generation(2), replacing: 1)
        }

        #expect(try await archive.withGeneration { $0 == original })

        let inventory = try await archive.reconcile()

        #expect(inventory.state == .ready)
        #expect(await governor.usage(.diskStateBytes) == inventory.measuredBytes)
    }

    @Test
    func freshBackendAndGovernorReadTheSameExplicitlyCommittedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let firstGovernor = ResourceGovernor()
        try await seedAndDrop(fixture, governor: firstGovernor)

        let retained = await firstGovernor.usage(.diskStateBytes)

        #expect(retained > 4_096)

        let archive = try await fixture.make(ResourceGovernor())

        #expect(await archive.status().measuredBytes > 4_096)

        _            = try await archive.start()
        let expected = fixture.generation(1)

        #expect(try await archive.withGeneration { $0 == expected })
        #expect(await firstGovernor.usage(.diskStateBytes) == retained)
    }

    private func seedAndDrop(
        _ fixture: Fixture,
        governor : ResourceGovernor
    ) async throws {
        let archive = try await fixture.make(governor)
        _           = try await archive.start()
        _           = try await archive.save(fixture.generation(1), replacing: nil)

        _ = await archive.suspend()
    }

    @Test
    func oversizedAndFutureCandidatesAreRejectedBeforeChangingTheRow() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)
        _            = try await archive.start()
        let original = fixture.generation(1)
        _            = try await archive.save(original, replacing: nil)

        for candidate in [
            SwiftDataArchiveGeneration(
                schemaVersion : 2,
                revision      : 2,
                verifiedDigest: "verified-digest",
                payload       : Data()
            ),
            SwiftDataArchiveGeneration(
                schemaVersion : 1,
                revision      : 2,
                verifiedDigest: "",
                payload       : Data()
            ),
            SwiftDataArchiveGeneration(
                schemaVersion : 1,
                revision      : 2,
                verifiedDigest: "verified-digest",
                payload       : Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)
            )
        ] {
            await #expect(throws: SwiftDataArchiveFailure.self) {
                try await archive.save(candidate, replacing: 1)
            }
        }

        #expect(try await archive.withGeneration { $0 == original })
        #expect(await archive.status().state == .ready)
    }

    @Test
    func anotherVerifiedPublisherCannotOpenTheStoredNamespace() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        try await seedAndDrop(fixture, governor: ResourceGovernor())

        let governor = ResourceGovernor()
        let archive  = try await SwiftDataArchive.make(
            identity: VerifiedAddonIdentity(
                publisher: "foreign.publisher",
                addonID  : fixture.identity.addonID
            ),
            root    : fixture.root,
            governor: governor
        )

        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.start() }
        #expect(await archive.status().state == .faulted)
        #expect(await governor.usage(.diskStateBytes) > 4_096)
    }

    @Test
    func observedPostSaveDebtPreservesCommitAndBlocksOnlyFurtherWrites() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let governor = ResourceGovernor()
        let observer = ControlledArchiveObserver()
        let archive  = try await SwiftDataArchive.make(
            identity: fixture.identity,
            root    : fixture.root,
            governor: governor,
            observer: observer
        )

        _ = try await archive.start()
        await observer.addAfterNextObservation(12 * 1_024 * 1_024)
        let expected = fixture.generation(1)
        let saved    = try await archive.save(expected, replacing: nil)

        #expect(saved.status.state == .overbudget)
        #expect(saved.status.ownerOverageBytes > 0)
        #expect(try await archive.withGeneration { $0 == expected })

        let debt = await governor.usage(.diskStateBytes)
        await governor.releaseAll(owner: fixture.identity.addonID)
        #expect(await governor.usage(.diskStateBytes) == debt)

        await #expect(throws: AddonFailure.self) {
            try await archive.save(fixture.generation(2), replacing: 1)
        }

        #expect(try await archive.withGeneration { $0 == expected })

        await observer.clearAdditionalBytes()
        #expect(try await archive.reconcile().state == .ready)
        #expect(try await archive.save(fixture.generation(2), replacing: 1).revision == 2)
    }

    @Test
    func initialOversizedStoreIsChargedWithoutOpeningSwiftData() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let store      = fixture.root.appendingPathComponent("archive.store")
        let descriptor = open(
            store.path,
            O_WRONLY | O_CREAT | O_EXCL,
            0o600
        )

        #expect(descriptor >= 0)

        guard descriptor >= 0 else { return }

        #expect(ftruncate(descriptor, 11 * 1_024 * 1_024) == 0)

        close(descriptor)

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)

        #expect(await archive.status().state == .overbudget)
        #expect(await governor.usage(.diskStateBytes) == 11 * 1_024 * 1_024 + 8_192)

        await #expect(throws: AddonFailure.self) { try await archive.start() }
        #expect(!FileManager.default.fileExists(atPath: store.path + "-wal"))
    }

    @Test
    func scopedCallbackKeepsMemoryProtectedWhileSuspensionDrainsIt() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)
        _            = try await archive.start()
        let gate     = ArchiveGate()
        let reading  = Task {
            try await archive.withGeneration { value in
                #expect(value == nil)

                await gate.enter()
                return true
            }
        }

        await gate.waitUntilEntered()
        let protected = await governor.usage(.admittedMemoryBytes)

        #expect(protected > 16_384)

        await governor.releaseAll(owner: fixture.identity.addonID)
        #expect(await governor.usage(.admittedMemoryBytes) == protected)

        let status = await archive.suspend()

        #expect(status.state == .suspended)
        #expect(status.isBusy)

        await #expect(throws: SwiftDataArchiveFailure.self) {
            try await archive.withGeneration { _ in false }
        }

        await gate.release()
        #expect(try await reading.value)
        #expect(await governor.usage(.admittedMemoryBytes) == 16_384)
        #expect(!(await archive.status().isBusy))
    }

    @Test
    func cancellationDuringPreflightPreventsACommitAndRefundsControlledMemory() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let governor = ResourceGovernor()
        let observer = ControlledArchiveObserver()
        let archive  = try await SwiftDataArchive.make(
            identity: fixture.identity,
            root    : fixture.root,
            governor: governor,
            observer: observer
        )

        _        = try await archive.start()
        let gate = ArchiveGate()
        await observer.gateNextObservation(gate)
        let saving = Task {
            try await archive.save(fixture.generation(1), replacing: nil)
        }

        await gate.waitUntilEntered()
        saving.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await saving.value }
        #expect(try await archive.withGeneration { $0 == nil })
        #expect(await governor.usage(.admittedMemoryBytes) == 16_384)
    }

    @Test(arguments: ["checksum", "schema", "digest"])
    func persistedInvalidGenerationNeverReachesTheHostCallback(_ corruption: String) async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        try await seedAndDrop(fixture, governor: ResourceGovernor())

        try await mutatePersistedRow(root: fixture.root, corruption: corruption)

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)
        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.start() }
        #expect(await archive.status().state == .faulted)
        #expect(await archive.inventoryStatus() == .complete)

        await #expect(throws: SwiftDataArchiveFailure.self) {
            try await archive.withGeneration { _ in
                Issue.record("Invalid persisted generation escaped into a host callback")
            }
        }

        #expect(await governor.usage(.diskStateBytes) > 4_096)
    }

    /// mutatePersistedRow uses the actual SwiftData model and save, not private SQLite table names.
    private func mutatePersistedRow(
        root      : URL,
        corruption: String
    ) async throws {
        try await Task.detached {
            let schema        = Schema([SwiftDataArchiveRow.self])
            let configuration = ModelConfiguration(
                "CascadeOwnerArchive",
                schema          : schema,
                url             : root.appendingPathComponent("archive.store"),
                cloudKitDatabase: .none
            )

            let container = try ModelContainer(for: schema, configurations: [configuration])

            let context             = ModelContext(container)
            context.autosaveEnabled = false
            context.undoManager     = nil
            let rows                = try context.fetch(FetchDescriptor<SwiftDataArchiveRow>())
            let row                 = try #require(rows.first)
            switch corruption {
                case "checksum":
                    row.checksum = Data([0])

                case "schema":
                    row.schemaVersion = 2

                default:
                    row.verifiedDigest = ""
            }

            try context.save()
        }.value
    }

    @Test
    func incompleteInventoryRetainsPriorDebtUntilACompleteObservation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let observer = ControlledArchiveObserver()
        let governor = ResourceGovernor()
        let archive  = try await SwiftDataArchive.make(
            identity: fixture.identity,
            root    : fixture.root,
            governor: governor,
            observer: observer
        )

        _ = try await archive.start()
        await observer.addAfterNextObservation(12 * 1_024 * 1_024)
        _ = try await archive.save(fixture.generation(1), replacing: nil)

        let prior = await governor.usage(.diskStateBytes)
        await observer.clearAdditionalBytes()
        await observer.setIncomplete(true)
        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.reconcile() }
        #expect(await archive.status().state == .faulted)
        #expect(await governor.usage(.diskStateBytes) == prior)

        await #expect(throws: SwiftDataArchiveFailure.self) {
            try await archive.withGeneration { _ in true }
        }

        await observer.setIncomplete(false)
        #expect(try await archive.reconcile().state == .ready)
        #expect(await governor.usage(.diskStateBytes) < prior)
    }

    @Test
    func suspensionAfterSaveStillReturnsTheKnownCommit() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let observer = ControlledArchiveObserver()
        let archive  = try await SwiftDataArchive.make(
            identity: fixture.identity,
            root    : fixture.root,
            governor: ResourceGovernor(),
            observer: observer
        )

        _        = try await archive.start()
        let gate = ArchiveGate()
        await observer.gateAfterNextObservation(gate)
        let expected = fixture.generation(1)
        let saving   = Task {
            try await archive.save(expected, replacing: nil)
        }

        await gate.waitUntilEntered()
        _ = await archive.suspend()
        await gate.release()
        let saved = try await saving.value

        #expect(saved.revision == 1)
        #expect(saved.status.state == .suspended)

        _ = try await archive.start()
        #expect(try await archive.withGeneration { $0 == expected })
    }

    @Test
    func nestedUnknownFilesAreAllCountedBeforeUseIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let directory = fixture.root.appendingPathComponent("unknown")
        try FileManager.default.createDirectory(
            at                         : directory,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )

        let file          = directory.appendingPathComponent("retained")
        let retainedBytes = Data(repeating: 8, count: 31)

        try retainedBytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        let governor = ResourceGovernor()
        let archive  = try await fixture.make(governor)

        #expect(await governor.usage(.diskStateBytes) == 12_319)
        #expect(await archive.status().state == .faulted)
    }

    @Test
    func strictStartupGrowthDenialDoesNotCreateFrameworkFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let governor = ResourceGovernor()
        _            = try await governor.admit(
            .diskState(bytes: 9 * 1_024 * 1_024),
            owner: fixture.identity.addonID
        )

        let archive = try await fixture.make(governor)
        await #expect(throws: AddonFailure.self) { try await archive.start() }
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("archive.store").path
        ))
        #expect(await governor.usage(.diskStateBytes) == 9 * 1_024 * 1_024 + 4_096)
        #expect(await governor.usage(.admittedMemoryBytes) == 16_384)
    }

    @Test
    func unsafeCompleteInventoryCannotRefundPriorDebt() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let observer = ControlledArchiveObserver()
        let governor = ResourceGovernor()
        let archive  = try await SwiftDataArchive.make(
            identity: fixture.identity,
            root    : fixture.root,
            governor: governor,
            observer: observer
        )

        _ = try await archive.start()
        await observer.addAfterNextObservation(12 * 1_024 * 1_024)
        _ = try await archive.save(fixture.generation(1), replacing: nil)

        let prior = await governor.usage(.diskStateBytes)
        await observer.clearAdditionalBytes()
        let store = fixture.root.appendingPathComponent("archive.store")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.path)

        let descriptor = open(fixture.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)

        guard descriptor >= 0 else {
            Issue.record("Could not inspect the real test root")
            return
        }

        defer { close(descriptor) }

        let unsafe = SwiftDataArchiveDirectory.inventory(root: fixture.root, descriptor: descriptor)

        #expect(unsafe.isComplete)
        #expect(unsafe.hasUnsafeEntries)

        await #expect(throws: SwiftDataArchiveFailure.self) { try await archive.reconcile() }
        #expect(await governor.usage(.diskStateBytes) == prior)
        #expect(await archive.status().state == .faulted)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)

        #expect(try await archive.reconcile().state == .ready)
        #expect(await governor.usage(.diskStateBytes) < prior)
    }

    @Test
    func scanCountsLargerCheckedFileSizeBeforeRejectingTheMismatch() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let store = fixture.root.appendingPathComponent("archive.store")
        let bytes = Data(repeating: 8, count: 7)

        try bytes.write(to: store)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)

        let descriptor = try KeyedStorageDirectory.openRoot(fixture.root)
        defer { close(descriptor) }

        let inventory = SwiftDataArchiveDirectory.inventory(
            root          : fixture.root,
            descriptor    : descriptor,
            fileInspection: GrowingArchiveFileInspection()
        )

        #expect(inventory.isComplete)
        #expect(inventory.hasUnsafeEntries)
        #expect(inventory.bytes == 8_192 + 101)
        #expect(try Data(contentsOf: store).count == 101)
    }
}
