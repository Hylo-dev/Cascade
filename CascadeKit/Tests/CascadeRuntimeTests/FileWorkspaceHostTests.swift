//
//  FileWorkspaceHostTests.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct FileWorkspaceHostTests {
    @Test
    func prepareAllItemsCoversEveryPageInOrderWithoutASnapshot() async throws {
        let fixture = try HostFixture()
        let host = try fixture.host()
        try await host.restore()
        var ids: [UUID] = []
        for batch in 0..<2 {
            let sources = try (0..<20).map { index in
                try fixture.file(name: "file-\(batch)-\(index).txt", contents: "\(batch)-\(index)")
            }
            ids += try await host.addOriginals(sources)
        }
        try await host.close()

        // A fresh process lifetime that never asks for a snapshot, as at launch.
        let restored = try fixture.host()
        try await restored.restore()
        let prepared = try await restored.prepareAllItems()
        #expect(prepared.map(\.itemID) == ids)

        // Items past the first 12-entry page stay deliverable.
        let last = try #require(prepared.last)
        try await restored.copy(last, to: fixture.output.appendingPathComponent(last.name))
        #expect(try String(contentsOf: fixture.output.appendingPathComponent(last.name), encoding: .utf8) == "1-19")
        try await restored.close()
    }

    @Test
    func renameOriginalPreservesContentsAndIdentityAcrossRestore() async throws {
        let fixture = try HostFixture()
        let host = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "before.txt", contents: "keep me")
        let id = try #require(try await host.addOriginals([source]).first)
        let before = try await host.snapshot()
        let oldPrepared = try #require(try await host.prepareItems(ids: [id]).first)
        try await host.renameExternalReference(id: id, newName: "after.txt", revision: before.revision)
        let renamedURL = source.deletingLastPathComponent().appendingPathComponent("after.txt")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: renamedURL, encoding: .utf8) == "keep me")
        let renamed = try await host.snapshot()
        #expect(renamed.entries.first?.id == id)
        #expect(renamed.entries.first?.name == "after.txt")
        #expect(renamed.entries.first?.availability == .available)
        await #expect(throws: FileWorkspaceError.unavailable) {
            try await host.copy(oldPrepared, to: fixture.output.appendingPathComponent("old.txt"))
        }
        try await host.close()
        let restored = try fixture.host()
        try await restored.restore()
        #expect(try await restored.snapshot().entries.first?.name == "after.txt")
        let prepared = try #require(try await restored.prepareItems(ids: [id]).first)
        try await restored.copy(prepared, to: fixture.output.appendingPathComponent(prepared.name))
        #expect(try String(contentsOf: renamedURL, encoding: .utf8) == "keep me")
        #expect(try String(contentsOf: fixture.output.appendingPathComponent("after.txt"), encoding: .utf8) == "keep me")
    }

    @Test
    func renameRejectsCollisionsAndInvalidNamesWithoutChangingTheOriginal() async throws {
        let fixture = try HostFixture()
        let host = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "source")
        let existing = try fixture.file(name: "existing.txt", contents: "existing")
        let id = try #require(try await host.addOriginals([source]).first)
        let before = try await host.snapshot()
        for name in ["", "..", "../escape.txt", "dir/name.txt", "bad:name", "existing.txt"] {
            await #expect(throws: (any Error).self) {
                try await host.renameExternalReference(id: id, newName: name, revision: before.revision)
            }
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "source")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
        #expect(try await host.snapshot().revision == before.revision)
        await #expect(throws: FileWorkspaceError.staleRevision) {
            try await host.renameExternalReference(id: id, newName: "after.txt", revision: before.revision + 1)
        }
    }

    @Test
    func snapshotPagesTwelveEntriesWithoutSkipping() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let sources = try (0..<25).map {
            try fixture.file(name: "item-\($0).txt", contents: "\($0)")
        }
        _ = try await host.addOriginals(sources)

        let first  = try await host.snapshot()
        let second = try await host.snapshot(cursor: try #require(first.nextCursor))
        let third  = try await host.snapshot(cursor: try #require(second.nextCursor))

        #expect(first.entries.count == 12)
        #expect(second.entries.count == 12)
        #expect(third.entries.count == 1)
        #expect((first.entries + second.entries + third.entries).map(\.name) == sources.map(\.lastPathComponent))
    }

    @Test
    func copyUsesPreparedLifetimeAndRemovesOnlyAfterDurableSuccess() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "original")
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("copied.txt")

        try await host.copy(prepared, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(try await host.snapshot().entries.isEmpty)
    }

    @Test
    func collisionNeverOverwritesAndKeepsTheEntry() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "source")
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("existing.txt")
        try Data("existing".utf8).write(to: destination)

        await #expect(throws: FileWorkspaceError.ioFailure) {
            try await host.copy(prepared, to: destination)
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "existing")
        #expect(try await host.snapshot().entries.map(\.id) == [id])
    }

    @Test
    func relinkPreservesIdentityAndOrderButInvalidatesPreparedLifetime() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let first = try fixture.file(name: "first.txt", contents: "first")
        let second = try fixture.file(name: "second.txt", contents: "second")
        let ids = try await host.addOriginals([first, second])
        let before = try await host.snapshot()
        let prepared = try #require(try await host.prepareItems(ids: [ids[0]]).first)
        try FileManager.default.removeItem(at: first)
        let replacement = try fixture.file(name: "replacement.txt", contents: "replacement")

        try await host.relinkExternalReference(
            id      : ids[0],
            to      : replacement,
            revision: before.revision
        )

        let after = try await host.snapshot()
        #expect(after.entries.map(\.id) == ids)
        #expect(after.entries.map(\.name) == ["replacement.txt", "second.txt"])
        #expect(after.revision == before.revision + 1)
        await #expect(throws: FileWorkspaceError.unavailable) {
            try await host.copy(
                prepared,
                to: fixture.output.appendingPathComponent("stale.txt")
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("stale.txt").path))
    }

    @Test
    func removingReferencePersistsWithoutDeletingTheOriginal() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "kept.txt", contents: "kept")
        let id = try #require(try await host.addOriginals([source]).first)
        let revision = try await host.snapshot().revision

        try await host.removeExternalReference(id: id, revision: revision)
        try await host.close()

        let reopened = try fixture.host()
        try await reopened.restore()
        #expect(try await reopened.snapshot().entries.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "kept")
    }

    @Test
    func concurrentPromiseCopiesAndRefreshAreSerializedWithoutLosingReceipts() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let first  = try fixture.file(name: "first.txt", contents: "first")
        let second = try fixture.file(name: "second.txt", contents: "second")
        let ids = try await host.addOriginals([first, second])
        let prepared = try await host.prepareItems(ids: ids)

        async let firstCopy: Void = host.copy(
            prepared[0],
            to: fixture.output.appendingPathComponent("first.txt")
        )
        async let secondCopy: Void = host.copy(
            prepared[1],
            to: fixture.output.appendingPathComponent("second.txt")
        )
        async let refresh = host.snapshot()
        _ = try await (firstCopy, secondCopy, refresh)

        #expect(try await host.snapshot().entries.isEmpty)
        #expect(try String(
            contentsOf: fixture.output.appendingPathComponent("first.txt"),
            encoding  : .utf8
        ) == "first")
        #expect(try String(
            contentsOf: fixture.output.appendingPathComponent("second.txt"),
            encoding  : .utf8
        ) == "second")
    }

    @Test
    func copyPreservesModeAndExtendedAttributes() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "tool", contents: "executable")
        #expect(chmod(source.path, 0o751) == 0)
        let attribute = Data("shelf-metadata".utf8)
        let attributeName = "com.example.cascade-shelf-test"
        let setResult = attribute.withUnsafeBytes { bytes in
            setxattr(source.path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
        }
        #expect(setResult == 0)
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("tool")

        try await host.copy(prepared, to: destination)

        var info = stat()
        #expect(stat(destination.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o751)
        let size = getxattr(destination.path, attributeName, nil, 0, 0, 0)
        #expect(size == attribute.count)
        var copiedAttribute = Data(count: max(0, size))
        let read = copiedAttribute.withUnsafeMutableBytes { bytes in
            getxattr(destination.path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
        }
        #expect(read == attribute.count)
        #expect(copiedAttribute == attribute)
    }

    @Test
    func cancellationAfterLeaseSettlesDeliveryAndHostCanReopen() async throws {
        let fixture = try HostFixture()
        let barrier = DeliveryLeaseBarrier()
        let host = try FileWorkspaceHost(
            directory        : fixture.workspace,
            governor         : fixture.governor,
            afterDeliveryLease: { await barrier.suspend() }
        )
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "source")
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("cancelled.txt")

        let copy = Task { try await host.copy(prepared, to: destination) }
        await barrier.waitUntilSuspended()
        copy.cancel()
        await barrier.resume()

        await #expect(throws: FileWorkspaceError.interrupted) { try await copy.value }
        #expect(try await host.snapshot().entries.map(\.id) == [id])
        try await host.close()
        let reopened = try fixture.host()
        try await reopened.restore()
        #expect(try await reopened.snapshot().entries.map(\.id) == [id])
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

private actor DeliveryLeaseBarrier {
    private var suspended = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspended = true
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters = []
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func resume() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private struct HostFixture {
    let base     : URL
    let workspace: URL
    let inputs   : URL
    let output   : URL
    let governor = ResourceGovernor()

    init() throws {
        base      = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        workspace = base.appendingPathComponent("workspace")
        inputs    = base.appendingPathComponent("inputs")
        output    = base.appendingPathComponent("output")
        for directory in [workspace, inputs, output] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
    }

    func host() throws -> FileWorkspaceHost {
        try FileWorkspaceHost(
            directory: workspace,
            governor : governor
        )
    }

    func file(name: String, contents: String) throws -> URL {
        let url = inputs.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
