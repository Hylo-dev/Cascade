//
//  FileWorkspaceHost.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

/// PreparedFile is an immutable capability for one exact shelf-entry lifetime.
/// It retains no descriptor or store pin and is invalid after removal, relinking or host restart.
public struct PreparedFile: Sendable {
    public let itemID        : UUID
    public let name          : String
    public let typeIdentifier: String
    public let ownership     : FileOwnership

    fileprivate let entry: FileWorkspacePreparedEntry

    fileprivate init(_ entry: FileWorkspacePreparedEntry) {
        itemID         = entry.id
        name           = entry.name
        typeIdentifier = entry.typeIdentifier
        ownership      = entry.ownership
        self.entry     = entry
    }
}

/// FileWorkspaceHost exposes the app's local shelf through the existing durable runtime store.
/// Its bounded gate serializes complete store flows, including delivery receipts.
public actor FileWorkspaceHost {
    private enum State {
        case initialized
        case open
        case closed
    }

    private static let pageSize       = 12
    private static let maximumWaiters = 32
    private static let copyChunkBytes = 64 * 1_024

    private let owner             : AddonID
    private let governor          : ResourceGovernor
    private let directory         : URL
    private let afterDeliveryLease: (@Sendable () async -> Void)?
    private var store   : FileWorkspaceStore?

    private var state = State.initialized
    private var closeRequested = false
    private var operationActive = false
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    /// Creates one facade, store and namespace lifetime for a host-owned shelf directory.
    public init(
        directory: URL,
        governor : ResourceGovernor
    ) throws {
        guard let owner = AddonID(rawValue: "app.cascade.file-shelf") else {
            throw FileWorkspaceError.ioFailure
        }
        self.owner             = owner
        self.governor          = governor
        self.directory         = directory.standardizedFileURL
        afterDeliveryLease = nil
    }

    /// Test-only assembly seam for suspending after a delivery owns its checked source lease.
    init(
        directory        : URL,
        governor         : ResourceGovernor,
        afterDeliveryLease: @escaping @Sendable () async -> Void
    ) throws {
        guard let owner = AddonID(rawValue: "app.cascade.file-shelf") else {
            throw FileWorkspaceError.ioFailure
        }
        self.owner              = owner
        self.governor           = governor
        self.directory          = directory.standardizedFileURL
        self.afterDeliveryLease = afterDeliveryLease
    }

    /// Restores and accounts the durable shelf before it becomes available.
    public func restore() async throws {
        try await withExclusive {
            guard self.state == .initialized, !self.closeRequested else {
                throw FileWorkspaceError.interrupted
            }
            do {
                let lifetime = try await self.governor.fileWorkspaceLifetime(
                    directory: self.directory,
                    owner    : self.owner
                )
                let store = FileWorkspaceStore(
                    directory  : self.directory,
                    owner      : self.owner,
                    resources  : self.governor,
                    persistence: FoundationFileWorkspacePersistence(directory: self.directory),
                    references : FoundationFileReferenceResolver(),
                    lifetime   : lifetime
                )
                try await store.restore()
                self.store = store
                self.state = .open
            } catch {
                self.state = .closed
                throw error
            }
        }
    }

    /// Closes this process lifetime permanently and releases retained in-memory charges.
    public func close() async throws {
        guard !closeRequested, state != .closed else { return }
        closeRequested = true
        do {
            try await withExclusive {
                guard self.state == .open else { throw FileWorkspaceError.interrupted }
                try await self.requireStore().close()
                self.store = nil
                self.state = .closed
            }
        } catch {
            state = .closed
            throw Self.map(error)
        }
    }

    /// Adds authorized regular-file URLs using the store's bookmark and identity validation.
    public func addOriginals(_ urls: [URL]) async throws -> [UUID] {
        try await withOpenExclusive { try await self.requireStore().addOriginals(urls) }
    }

    /// Returns one cursor-bound page sized to fit the shared presentation action limit.
    public func snapshot(cursor: String? = nil) async throws -> FileWorkspaceSnapshot {
        try await withOpenExclusive {
            try await self.requireStore().snapshot(cursor: cursor, pageSize: Self.pageSize)
        }
    }

    /// Forgets one external reference at the caller's observed revision.
    public func removeExternalReference(
        id      : UUID,
        revision: UInt64
    ) async throws {
        try await withOpenExclusive {
            try await self.requireStore().removeExternalReference(id: id, revision: revision)
        }
    }

    /// Replaces one external bookmark while preserving its item ID and order.
    public func relinkExternalReference(
        id      : UUID,
        to url  : URL,
        revision: UInt64
    ) async throws {
        try await withOpenExclusive {
            try await self.requireStore().relinkExternalReference(
                id      : id,
                to      : url,
                revision: revision
            )
        }
    }

    /// Renames the original file without overwriting another file, preserving its shelf ID.
    public func renameExternalReference(id: UUID, newName: String, revision: UInt64) async throws {
        try await withOpenExclusive {
            try await self.requireStore().renameExternalReference(
                id: id, newName: newName, revision: revision
            )
        }
    }

    /// Prepares deferred native transfers without opening files or pinning store entries.
    public func prepareItems(ids: [UUID]) async throws -> [PreparedFile] {
        try await withOpenExclusive {
            try await self.requireStore().prepareItems(ids: ids).map(PreparedFile.init)
        }
    }

    /// Prepares every shelf item from the manifest alone, without resolving bookmarks.
    public func prepareAllItems() async throws -> [PreparedFile] {
        try await withOpenExclusive {
            try await self.requireStore().prepareAllItems().map(PreparedFile.init)
        }
    }

    /// Copies one prepared item to a new destination and removes it only after durable success.
    public func copy(
        _ prepared   : PreparedFile,
        to destination: URL
    ) async throws {
        try await withOpenExclusive {
            let reservation: ResourceReservation
            do {
                reservation = try await self.governor.admit(
                    .temporaryMemory(bytes: Self.copyChunkBytes),
                    owner: self.owner
                )
            } catch {
                throw Self.map(error)
            }

            do {
                try await self.copyReserved(prepared, to: destination)
                try await self.governor.release(reservation.id, owner: self.owner)
            } catch {
                try? await self.governor.release(reservation.id, owner: self.owner)
                throw Self.map(error)
            }
        }
    }

    /// Holds a checked reference lease while the host previews or reveals one exact prepared item.
    public func withCheckedURL<Result: Sendable>(
        for prepared: PreparedFile,
        operation   : @Sendable (URL) async throws -> Result
    ) async throws -> Result {
        guard prepared.ownership == .externalReference else {
            throw FileWorkspaceError.unsupported
        }
        let lease = try await withOpenExclusive {
            try await self.requireStore().lease(for: prepared.entry)
        }
        defer { lease.close() }
        return try await operation(lease.url)
    }

    private func copyReserved(
        _ prepared   : PreparedFile,
        to destination: URL
    ) async throws {
        let store = try requireStore()
        let deliveryID = try await store.beginDelivery(prepared.entry)
        var lease: FileReferenceLease?
        do {
            let acquired = try await store.leaseForDelivery(
                deliveryID,
                itemID: prepared.itemID
            )
            lease = acquired
            if let afterDeliveryLease { await afterDeliveryLease() }
            try Task.checkCancellation()
            try Self.copyDescriptor(acquired.descriptor, to: destination)
            acquired.close()
            lease = nil
            try await Self.finishDelivery(
                store,
                deliveryID: deliveryID,
                itemID    : prepared.itemID,
                result    : .success(())
            )
        } catch {
            lease?.close()
            let failure = Self.map(error)
            do {
                try await Self.finishDelivery(
                    store,
                    deliveryID: deliveryID,
                    itemID    : prepared.itemID,
                    result    : .failure(failure)
                )
            } catch {
                throw Self.map(error)
            }
            throw failure
        }
    }

    private func withOpenExclusive<Result: Sendable>(
        _ body: () async throws -> Result
    ) async throws -> Result {
        guard !closeRequested else { throw FileWorkspaceError.interrupted }
        return try await withExclusive {
            guard self.state == .open, !self.closeRequested else {
                throw FileWorkspaceError.interrupted
            }
            return try await body()
        }
    }

    private func requireStore() throws -> FileWorkspaceStore {
        guard let store else { throw FileWorkspaceError.ioFailure }
        return store
    }

    private static func finishDelivery(
        _ store      : FileWorkspaceStore,
        deliveryID  : UUID,
        itemID      : UUID,
        result      : Result<Void, FileWorkspaceError>
    ) async throws {
        try await Task.detached {
            try await store.finishDelivery(deliveryID, itemID: itemID, result: result)
        }.value
    }

    private func withExclusive<Result: Sendable>(
        _ body: () async throws -> Result
    ) async throws -> Result {
        do { try await acquirePermit() }
        catch { throw Self.map(error) }
        defer { releasePermit() }
        do { return try await body() }
        catch { throw Self.map(error) }
    }

    private func acquirePermit() async throws {
        try Task.checkCancellation()
        guard operationActive else {
            operationActive = true
            return
        }
        guard waiterOrder.count < Self.maximumWaiters else {
            throw FileWorkspaceError.interrupted
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiterOrder.append(waiterID)
                    waiters[waiterID] = continuation
                }
            }
        }, onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        })
        do { try Task.checkCancellation() }
        catch {
            releasePermit()
            throw error
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waiterOrder.removeAll { $0 == id }
        continuation.resume(throwing: CancellationError())
    }

    private func releasePermit() {
        while let id = waiterOrder.first {
            waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume()
            return
        }
        operationActive = false
    }

    private static func copyDescriptor(
        _ source     : Int32,
        to destination: URL
    ) throws {
        guard destination.isFileURL,
              destination.path.hasPrefix("/"),
              !destination.path.utf8.contains(0),
              !destination.lastPathComponent.isEmpty,
              !destination.lastPathComponent.contains("/") else {
            throw FileWorkspaceError.unsupported
        }
        let parentURL = destination.deletingLastPathComponent()
        var sourceBefore = stat()
        guard fstat(source, &sourceBefore) == 0,
              sourceBefore.st_mode & S_IFMT == S_IFREG else {
            throw FileWorkspaceError.unavailable
        }
        let parent = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard parent >= 0 else { throw FileWorkspaceError.ioFailure }
        defer { Darwin.close(parent) }

        let leaf = destination.lastPathComponent
        let output = openat(
            parent,
            leaf,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard output >= 0 else { throw FileWorkspaceError.ioFailure }
        var identity: FileReferenceIdentity?
        var outputOpen = true
        var keep = false
        defer {
            if outputOpen { Darwin.close(output) }
            if !keep, let identity {
                removeOutput(parent: parent, leaf: leaf, identity: identity)
            }
        }

        var info = stat()
        guard fstat(output, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid() else {
            throw FileWorkspaceError.ioFailure
        }
        identity = FileReferenceIdentity(
            device    : UInt64(info.st_dev),
            inode     : UInt64(info.st_ino),
            generation: UInt64(info.st_gen)
        )

        var buffer = Data(count: copyChunkBytes)
        var copiedBytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = try buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                while true {
                    let count = Darwin.read(source, base, bytes.count)
                    if count < 0, errno == EINTR { continue }
                    guard count >= 0 else { throw FileWorkspaceError.ioFailure }
                    return count
                }
            }
            if count == 0 { break }
            let next = copiedBytes.addingReportingOverflow(Int64(count))
            guard !next.overflow else { throw FileWorkspaceError.ioFailure }
            copiedBytes = next.partialValue
            try buffer.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < count {
                    let written = Darwin.write(output, base.advanced(by: offset), count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { throw FileWorkspaceError.ioFailure }
                    offset += written
                }
            }
        }
        guard fcopyfile(
            source,
            output,
            nil,
            copyfile_flags_t(COPYFILE_STAT | COPYFILE_XATTR)
        ) == 0 else {
            throw FileWorkspaceError.ioFailure
        }
        var sourceAfter = stat()
        var outputAfter = stat()
        guard fstat(source, &sourceAfter) == 0,
              fstat(output, &outputAfter) == 0,
              copiedBytes == sourceBefore.st_size,
              outputAfter.st_size == sourceBefore.st_size,
              sourceAfter.st_dev == sourceBefore.st_dev,
              sourceAfter.st_ino == sourceBefore.st_ino,
              sourceAfter.st_gen == sourceBefore.st_gen,
              sourceAfter.st_size == sourceBefore.st_size,
              sourceAfter.st_mtimespec.tv_sec == sourceBefore.st_mtimespec.tv_sec,
              sourceAfter.st_mtimespec.tv_nsec == sourceBefore.st_mtimespec.tv_nsec,
              sourceAfter.st_ctimespec.tv_sec == sourceBefore.st_ctimespec.tv_sec,
              sourceAfter.st_ctimespec.tv_nsec == sourceBefore.st_ctimespec.tv_nsec,
              fsync(output) == 0 else {
            throw FileWorkspaceError.ioFailure
        }
        let closeResult = Darwin.close(output)
        outputOpen = false
        guard closeResult == 0, fsync(parent) == 0 else { throw FileWorkspaceError.ioFailure }
        keep = true
    }

    private static func removeOutput(
        parent  : Int32,
        leaf    : String,
        identity: FileReferenceIdentity
    ) {
        let descriptor = openat(parent, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        var info = stat()
        let same = fstat(descriptor, &info) == 0
            && info.st_mode & S_IFMT == S_IFREG
            && UInt64(info.st_dev) == identity.device
            && UInt64(info.st_ino) == identity.inode
            && UInt64(info.st_gen) == identity.generation
        Darwin.close(descriptor)
        if same, unlinkat(parent, leaf, 0) == 0 { _ = fsync(parent) }
    }

    private static func map(_ error: any Error) -> FileWorkspaceError {
        if let error = error as? FileWorkspaceError { return error }
        if error is CancellationError { return .interrupted }
        if let failure = error as? AddonFailure, failure.code == .resourceDenied {
            return .quotaExceeded
        }
        return .ioFailure
    }
}
