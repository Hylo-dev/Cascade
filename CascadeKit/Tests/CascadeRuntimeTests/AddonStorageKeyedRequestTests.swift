//
//  AddonStorageKeyedRequestTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite
struct AddonStorageKeyedRequestTests {
    /// Fixture retains two verified namespaces over real secure directories and a shared governor.
    private struct Fixture {
        let root      : URL
        let keyedRoot : URL
        let identities: [VerifiedAddonIdentity]
        let governor = ResourceGovernor()
        let gate: KeyedResourceGate
        let faults = KeyedFileFaults()
        let coordinator: AddonStorageCoordinator

        /// Fixture constructs only host-owned directories; backend readiness remains an explicit step.
        init() async throws {
            root = URL(fileURLWithPath: "/private/tmp/cascade-keyed-request-\(UUID())")
            keyedRoot = root.appendingPathComponent("keyed")
            let checkpoint = root.appendingPathComponent("checkpoints")
            let archive    = root.appendingPathComponent("archives")
            for directory in [root, keyedRoot, checkpoint, archive] {
                try FileManager.default.createDirectory(
                    at                         : directory,
                    withIntermediateDirectories: false,
                    attributes                 : [.posixPermissions: 0o700]
                )
            }
            identities = try ["one", "two"].map { name in
                VerifiedAddonIdentity(
                    publisher: "publisher." + name,
                    addonID  : try #require(AddonID(rawValue: "com.example.keyed-request." + name))
                )
            }
            gate = KeyedResourceGate(governor)
            coordinator = try await AddonStorageCoordinator.make(
                checkpointRoot: checkpoint,
                keyedRoot     : keyedRoot,
                archiveRoot   : archive,
                registrations : identities.map {
                    StateRegistration(
                        identity            : $0,
                        maximumSchemaVersion: 1
                    )
                },
                governor           : governor,
                resourceAccess     : gate,
                keyedFileOperations: faults
            )
        }

        /// start returns a fresh capability after the complete registry barrier succeeds.
        func start() async throws -> AddonStorageCoordinator.Owner {
            try await coordinator.start()
            return try await coordinator.owner(for: identities[0])
        }

        /// request creates the already-validated value that a future authenticated caller would submit.
        func request(
            _ operation: StorageOperation,
            key        : String = "key",
            value      : Data? = nil
        ) throws -> StorageRequest {
            try StorageRequest(
                requestID: UUID(),
                operation: operation,
                key      : key,
                value    : value
            )
        }

        func file(
            key  : String = "key",
            index: Int = 0
        ) throws -> URL {
            try AddonKeyedStorageTests.valueFile(
                keyedRoot,
                identity: identities[index],
                key     : key
            )
        }

        /// diskValue validates the actual record while a forwarded governor return is held.
        func diskValue(
            key  : String = "key",
            index: Int = 0
        ) throws -> Data? {
            let file = try file(
                key  : key,
                index: index
            )
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try KeyedStorageRecord.decode(
                Data(contentsOf: file),
                key         : Data(key.utf8),
                namespace   : KeyedStorageRecord.namespaceDigest(identities[index]),
                storageClass: .data
            ).value
        }

        func removeFiles() { try? FileManager.default.removeItem(at: root) }
    }

    @Test(
        arguments: [StorageOperation.write, .remove],
        [false, true]
    )
    func knownMutationSurvivesCloseOrCancellationAfterFileVisibility(
        operation: StorageOperation,
        cancel   : Bool
    ) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        if operation == .write {
            await fixture.gate.arm(
                .release,
                skipping: 1
            )
        } else {
            await fixture.gate.arm(.diskResize)
        }
        let request = try fixture.request(
            operation,
            value: operation == .write ? Data([2]) : nil
        )
        let task = Task {
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: owner
            )
        }
        await fixture.gate.wait()
        do {
            // Native record visibility identifies the commit phase, not a guessed gate count.
            #expect(try fixture.diskValue() == (operation == .write ? Data([2]) : nil))
            if cancel {
                task.cancel()
            } else {
                #expect(try await fixture.coordinator.close() == .draining)
            }
        } catch {
            await fixture.gate.resume()
            _ = await task.value
            throw error
        }
        await fixture.gate.resume()
        #expect(await task.value == .acknowledged)
        #expect(try await fixture.coordinator.close() == .closed)
        let fresh = try await fixture.start()
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: fresh
            ) == .read(operation == .write ? Data([2]) : nil)
        )
        _ = try await fixture.coordinator.close()
    }

    @Test
    func fullValuesEmptyMissingAndOwnerIsolationUseOnlyDataNamespace() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let first      = try await fixture.start()
        let second     = try await fixture.coordinator.owner(for: fixture.identities[1])
        let maximumKey = String(
            repeating: "é",
            count    : 128
        )
        let full = Data(
            repeating: 255,
            count    : 65_536
        )
        // Establish both real backend disk-pool reservations before measuring operation-only retention.
        try await fixture.coordinator.write(
            Data([0]),
            key  : "seed",
            owner: first
        )
        try await fixture.coordinator.write(
            Data([0]),
            key  : "seed",
            owner: second
        )
        let before = await fixture.governor.usage(.retainedStateBytes)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .write,
                    key  : maximumKey,
                    value: full
                ),
                owner: first
            ) == .acknowledged
        )
        #expect(try fixture.diskValue(key: maximumKey) == full)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .read,
                    key: maximumKey
                ),
                owner: first
            ) == .read(full)
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .read,
                    key: maximumKey
                ),
                owner: second
            ) == .read(nil)
        )
        #expect(
            try await fixture.coordinator.read(
                key         : maximumKey,
                owner       : first,
                storageClass: .cache
            ) == nil
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .write,
                    value: Data()
                ),
                owner: first
            ) == .acknowledged
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: first
            ) == .read(Data())
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .read,
                    key: "missing"
                ),
                owner: first
            ) == .read(nil)
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .write,
                    value: Data([9])
                ),
                owner: second
            ) == .acknowledged
        )
        let otherDisk = await fixture.governor.usage(
            .diskStateBytes,
            owner: fixture.identities[1].addonID
        )
        for _ in 0..<2 {
            #expect(
                try await fixture.coordinator.executeKeyedRequest(
                    fixture.request(.remove),
                    owner: first
                ) == .acknowledged
            )
        }
        #expect(try fixture.diskValue() == nil)
        #expect(try fixture.diskValue(index: 1) == Data([9]))
        #expect(
            await fixture.governor.usage(
                .diskStateBytes,
                owner: fixture.identities[1].addonID
            ) == otherDisk
        )
        // Record files have disk charges; operations leave no new permanent state reservation.
        #expect(await fixture.governor.usage(.retainedStateBytes) == before)
        _ = try await fixture.coordinator.close()
    }

    @Test
    func ownerEpochReadinessAndPreCancellationRefuseBeforeDiskWork() async throws {
        let fixture = try await Fixture()
        let foreign = try await Fixture()
        defer {
            fixture.removeFiles()
            foreign.removeFiles()
        }
        let foreignOwner = try await foreign.start()
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: foreignOwner
            ) == .refused(.unavailable)
        )
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        let request = try fixture.request(
            .write,
            value: Data([2])
        )
        #expect(
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: foreignOwner
            ) == .refused(.invalidOwner)
        )
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await fixture.coordinator.executeKeyedRequest(
                request,
                owner: owner
            )
        }
        #expect(await cancelled.value == .refused(.cancelled))
        #expect(try fixture.diskValue() == Data([1]))
        _ = try await fixture.coordinator.close()
        #expect(
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: owner
            ) == .refused(.unavailable)
        )
        let fresh = try await fixture.start()
        #expect(
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: owner
            ) == .refused(.invalidOwner)
        )
        #expect(try fixture.diskValue() == Data([1]))
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: fresh
            ) == .read(Data([1]))
        )
        _ = try await fixture.coordinator.close()
        _ = try await foreign.coordinator.close()
    }

    @Test(arguments: [KeyedResourceGate.Point.temporary, .diskResize])
    func cancellationAfterHandoffCanBeUnknownWithoutMutation(point: KeyedResourceGate.Point) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        await fixture.gate.arm(point)
        let request = try fixture.request(
            .write,
            value: Data([2])
        )
        let task = Task {
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: owner
            )
        }
        await fixture.gate.wait()
        do {
            #expect(try fixture.diskValue() == Data([1]))
            #expect(
                await fixture.coordinator.executeKeyedRequest(
                    request,
                    owner: owner
                ) == .refused(.busy)
            )
            task.cancel()
        } catch {
            await fixture.gate.resume()
            _ = await task.value
            throw error
        }
        await fixture.gate.resume()
        #expect(await task.value == .outcomeUnknown)
        #expect(try fixture.diskValue() == Data([1]))
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .read(Data([1]))
        )
        _ = try await fixture.coordinator.close()
    }

    @Test(arguments: [false, true])
    func readBytesDoNotEscapeCloseOrCancellation(cancel: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([7]),
            key  : "key",
            owner: owner
        )
        await fixture.gate.arm(.release)
        let request = try fixture.request(.read)
        let task    = Task {
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: owner
            )
        }
        await fixture.gate.wait()
        do {
            #expect(try fixture.diskValue() == Data([7]))
            if cancel { task.cancel() } else { #expect(try await fixture.coordinator.close() == .draining) }
        } catch {
            await fixture.gate.resume()
            _ = await task.value
            throw error
        }
        await fixture.gate.resume()
        #expect(await task.value == .refused(cancel ? .cancelled : .unavailable))
        _ = try await fixture.coordinator.close()
        let fresh = try await fixture.start()
        #expect(
            await fixture.coordinator.executeKeyedRequest(
                request,
                owner: fresh
            ) == .read(Data([7]))
        )
        _ = try await fixture.coordinator.close()
    }

    @Test(arguments: [StorageOperation.write, .remove])
    func postVisibilityDirectorySyncFailureReportsUncertainty(operation: StorageOperation) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        let before      = await fixture.governor.usage(.diskStateBytes)
        let file        = try fixture.file()
        let disappeared =
            operation == .write ? file.deletingLastPathComponent().appendingPathComponent(".pending") : file
        fixture.faults.failDirectorySync(afterDisappearanceOf: disappeared)
        let result = try await fixture.coordinator.executeKeyedRequest(
            fixture.request(
                operation,
                value: operation == .write ? Data([2]) : nil
            ),
            owner: owner
        )
        #expect(result == .outcomeUnknown)
        #expect(fixture.faults.injectedDirectoryFailures == 1)
        #expect(try fixture.diskValue() == (operation == .write ? Data([2]) : nil))
        let expectedDisk =
            operation == .write ? before : before - (4_096 + KeyedStorageRecord.headerBytes + 3 + 1)
        #expect(await fixture.governor.usage(.diskStateBytes) == expectedDisk)
        fixture.faults.set()
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .read(operation == .write ? Data([2]) : nil)
        )
        _ = try await fixture.coordinator.close()
        let fresh = try await fixture.start()
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: fresh
            ) == .read(operation == .write ? Data([2]) : nil)
        )
        _ = try await fixture.coordinator.close()
    }

    @Test
    func quotaAndIOAfterMutationHandoffStayUnknownAndReadErrorsStayBounded() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        let memory = await fixture.governor.usage(
            .admittedMemoryBytes,
            owner: fixture.identities[0].addonID
        )
        let filler = try await fixture.governor.admit(
            .temporaryMemory(bytes: 128 * 1_024 * 1_024 - memory),
            owner: fixture.identities[0].addonID
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .write,
                    value: Data([2])
                ),
                owner: owner
            ) == .outcomeUnknown
        )
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .refused(.readFailed(.resourceDenied))
        )
        #expect(try fixture.diskValue() == Data([1]))
        try await fixture.governor.release(
            filler.id,
            owner: filler.owner
        )
        fixture.faults.set(write: true)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(
                    .write,
                    value: Data([2])
                ),
                owner: owner
            ) == .outcomeUnknown
        )
        #expect(try fixture.diskValue() == Data([1]))
        fixture.faults.set(unlink: true)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.remove),
                owner: owner
            ) == .outcomeUnknown
        )
        fixture.faults.set()
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .read(Data([1]))
        )
        let file     = try fixture.file()
        let original = try Data(contentsOf: file)
        try Data([0]).write(to: file)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .refused(.readFailed(.dependencyUnavailable))
        )
        try original.write(to: file)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .read(Data([1]))
        )
        _ = try await fixture.coordinator.close()
    }

    @Test
    func futureRecordReadReportsVersionConflictWithoutReturningBytes() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        let file     = try fixture.file()
        let original = try Data(contentsOf: file)
        var future   = original
        future[8] = 2
        try future.write(to: file)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .refused(.readFailed(.versionConflict))
        )
        try original.write(to: file)
        #expect(
            try await fixture.coordinator.executeKeyedRequest(
                fixture.request(.read),
                owner: owner
            ) == .read(Data([1]))
        )
        _ = try await fixture.coordinator.close()
    }

    @Test
    func existingGenericWriteStillRejectsRevokedReturnAfterVisibility() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeFiles() }
        let owner = try await fixture.start()
        try await fixture.coordinator.write(
            Data([1]),
            key  : "key",
            owner: owner
        )
        await fixture.gate.arm(
            .release,
            skipping: 1
        )
        let task = Task {
            try await fixture.coordinator.write(
                Data([2]),
                key  : "key",
                owner: owner
            )
        }
        await fixture.gate.wait()
        do {
            #expect(try fixture.diskValue() == Data([2]))
            #expect(try await fixture.coordinator.close() == .draining)
        } catch {
            await fixture.gate.resume()
            _ = await task.result
            throw error
        }
        await fixture.gate.resume()
        await #expect(throws: AddonStorageCoordinator.Failure.unavailable) { try await task.value }
        _ = try await fixture.coordinator.close()
    }
}
