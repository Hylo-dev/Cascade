import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct StateMigrationTests {
    @Test func migrationCommitsValidatedCandidateAndRejectsStaleTicket() async throws {
        let root = try AddonStateStoreTests.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = AddonStateStoreTests.identity
        let store = try await AddonStateStoreTests.openStore(root: root, identities: [identity],
                                                           maximumSchemaVersion: 3)
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let migration = try await store.beginMigration(to: 2, owner: owner)
        #expect(migration.source.data == Data([1]))
        try await store.stageMigration(Data([2]), ticket: migration.ticket, owner: owner)
        #expect(try await store.read(owner: owner)?.schemaVersion == 1)
        try await store.commitMigration(migration.ticket, owner: owner)
        #expect(try await store.read(owner: owner)?.schemaVersion == 2)
        let stale = try await store.beginMigration(to: 3, owner: owner)
        try await store.write(Data([4]), schemaVersion: 2, owner: owner)
        await #expect(throws: StateStoreFailure.staleRevision) {
            try await store.stageMigration(Data([3]), ticket: stale.ticket, owner: owner)
        }
        #expect(try await store.read(owner: owner)?.data == Data([4]))
        try await store.close()
    }

    @Test func migrationCancellationAndRevocationKeepOldState() async throws {
        let root = try AddonStateStoreTests.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await AddonStateStoreTests.openStore(root: root, identities: [AddonStateStoreTests.identity],
                                                 maximumSchemaVersion: 2)
        let owner = try await store.owner(for: AddonStateStoreTests.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let migration = try await store.beginMigration(to: 2, owner: owner)
        try await store.stageMigration(Data([2]), ticket: migration.ticket, owner: owner)
        try await store.cancelMigration(migration.ticket, owner: owner)
        await #expect(throws: StateStoreFailure.invalidTicket) {
            try await store.commitMigration(migration.ticket, owner: owner)
        }
        let revoked = try await store.beginMigration(to: 2, owner: owner)
        try await store.revoke(owner: owner)
        await #expect(throws: StateStoreFailure.invalidOwner) {
            try await store.stageMigration(Data([3]), ticket: revoked.ticket, owner: owner)
        }
        let newOwner = try await store.owner(for: AddonStateStoreTests.identity)
        #expect(try await store.read(owner: newOwner)?.data == Data([1]))
        try await store.close()
    }

    @Test func failedOrTamperedCandidatePreservesOldCheckpoint() async throws {
        let root = try AddonStateStoreTests.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let governor = ResourceGovernor()
        let store = try await AddonStateStoreTests.openStore(root: root, identities: [AddonStateStoreTests.identity],
                                                 maximumSchemaVersion: 2, governor: governor)
        let owner = try await store.owner(for: AddonStateStoreTests.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let migration = try await store.beginMigration(to: 2, owner: owner)
        let usage = await governor.usage(.diskBytes)
        await #expect(throws: StateStoreFailure.oversized) {
            try await store.stageMigration(Data(repeating: 0, count: 65_537), ticket: migration.ticket, owner: owner)
        }
        #expect(await governor.usage(.diskBytes) == usage)
        try await store.stageMigration(Data([2]), ticket: migration.ticket, owner: owner)
        let file = try #require(FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "stage" })
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 64)
        try handle.write(contentsOf: Data([3]))
        try handle.close()
        await #expect(throws: StateStoreFailure.corrupt) {
            try await store.commitMigration(migration.ticket, owner: owner)
        }
        #expect(try await store.read(owner: owner)?.data == Data([1]))
        try await store.cancelMigration(migration.ticket, owner: owner)
        #expect(await governor.usage(.diskBytes) == usage)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        try await store.close()
    }


    @Test func pendingSnapshotsAcquireActualCapacityAndReleaseOnlyTheirReservations() async throws {
        let root = try AddonStateStoreTests.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let schemas = (0..<3).map {
            (VerifiedAddonIdentity(publisher: "migration", addonID: AddonID(rawValue: "com.example.migration\($0)")!),
             UInt32(3))
        }
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 450_000))
        let unrelated = try await governor.admit(.job, owner: AddonStateStoreTests.identity.addonID)
        let store = try await AddonStateStoreTests.openRegistered(root: root, schemas: schemas, governor: governor)
        var owners: [StateOwner] = []
        let payload = Data(repeating: 1, count: 65_536)
        for (identity, _) in schemas {
            let owner = try await store.owner(for: identity)
            owners.append(owner)
            try await store.write(payload, schemaVersion: 1, owner: owner)
        }
        let baseline = await governor.usage(.retainedStateBytes)
        let first = try await store.beginMigration(to: 2, owner: owners[0])
        try await store.stageMigration(payload, ticket: first.ticket, owner: owners[0])
        let second = try await store.beginMigration(to: 2, owner: owners[1])
        try await store.stageMigration(payload, ticket: second.ticket, owner: owners[1])
        #expect(await governor.usage(.retainedStateBytes) > baseline + 390_000)
        let full = await governor.usage(.retainedStateBytes)
        let disk = await governor.usage(.diskBytes)
        await #expect(throws: AddonFailure.self) {
            try await store.stage(payload, schemaVersion: 1, owner: owners[2])
        }
        await #expect(throws: AddonFailure.self) { try await store.beginMigration(to: 2, owner: owners[2]) }
        #expect(await governor.usage(.retainedStateBytes) == full)
        #expect(await governor.usage(.diskBytes) == disk)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        let filler = try await governor.admit(.state(bytes: 450_000 - full - 1_024),
                                              owner: AddonStateStoreTests.identity.addonID)
        #expect(await governor.usage(.retainedStateBytes) == 450_000)
        try await store.revoke(owner: owners[0])
        #expect(await governor.usage(.retainedStateBytes) < 450_000 - 190_000)
        try await governor.release(filler.id, owner: filler.owner)
        #expect(await governor.usage(.jobs) == 1)
        let fresh = try await store.owner(for: schemas[0].0)
        await #expect(throws: StateStoreFailure.invalidTicket) {
            try await store.stageMigration(payload, ticket: first.ticket, owner: fresh)
        }
        let third = try await store.beginMigration(to: 2, owner: owners[2])
        try await store.stageMigration(payload, ticket: third.ticket, owner: owners[2])
        try await store.cancelMigration(second.ticket, owner: owners[1])
        try await store.commitMigration(third.ticket, owner: owners[2])
        #expect(await governor.usage(.retainedStateBytes) == baseline)
        let removal = try await store.beginMigration(to: 3, owner: owners[2])
        try await store.stageMigration(payload, ticket: removal.ticket, owner: owners[2])
        try await store.removeUserData(owner: owners[2])
        try await store.close()
        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        #expect(await governor.usage(.jobs) == 1)
        try await governor.release(unrelated.id, owner: unrelated.owner)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

}
