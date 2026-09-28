//
//  SwiftDataArchiveDirectory.swift
//  CascadeKit
//

import Darwin
import Foundation

/// SwiftDataArchiveInventory reports known file lengths even when a scan cannot finish.
/// An incomplete observation can increase a ledger, but cannot prove any retained bytes gone.
struct SwiftDataArchiveInventory: Sendable {
    let bytes            : Int
    let isComplete       : Bool
    let hasUnsafeEntries : Bool
    let hasUnknownEntries: Bool

    var permitsFrameworkAccess: Bool {
        isComplete && !hasUnsafeEntries && !hasUnknownEntries
    }
}

/// SwiftDataArchiveObserving confines test delays to real filesystem observations.
/// Implementations must inventory the held root; successful test observations may add
/// test-owned files or conservatively increase measured bytes, never omit actual files.
protocol SwiftDataArchiveObserving: Sendable {
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory
}

/// NativeSwiftDataArchiveObserver performs bounded descriptor-relative scans off MainActor.
struct NativeSwiftDataArchiveObserver: SwiftDataArchiveObserving {
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        SwiftDataArchiveDirectory.inventory(
            root      : root,
            descriptor: descriptor
        )
    }
}

/// SwiftDataArchiveDirectory reuses held-directory safeguards while counting unknown entries.
/// SwiftData itself opens a URL: inode comparisons detect replacement but do not turn its
/// framework-managed opens into descriptor-relative operations.
enum SwiftDataArchiveDirectory {
    static let entryBytes             = 4_096
    private static let maximumEntries = 4_096
    private static let maximumDepth   = 8
    private static let managedNames: Set<String> = [
        "archive.store", "archive.store-wal", "archive.store-shm", "archive.store-journal"
    ]

    private struct Scan {
        var bytes             = entryBytes
        var entries           = 0
        var isComplete        = true
        var hasUnsafeEntries  = false
        var hasUnknownEntries = false
    }

    /// validateRootURL bounds the complete URL before the backend retains it.
    static func validateRootURL(_ root: URL) throws {
        guard root.baseURL == nil,
              root.isFileURL,
              root.absoluteString.utf8.count <= 4_096,
              root.query == nil,
              root.fragment == nil,
              root.path.hasPrefix("/") else {
            throw SwiftDataArchiveFailure.invalidConfiguration
        }
    }

    /// validateHeldRoot detects a replaced path without releasing the retained lock.
    static func validateHeldRoot(
        root      : URL,
        descriptor: Int32
    ) throws {
        try KeyedStorageDirectory.validateDirectory(descriptor)
        var held  = stat()
        var named = stat()
        let heldResult = fstat(
            descriptor,
            &held
        )
        let namedResult = lstat(
            root.path,
            &named
        )
        guard heldResult == 0,
              namedResult == 0,
              named.st_mode & S_IFMT == S_IFDIR,
              held.st_dev == named.st_dev,
              held.st_ino == named.st_ino else {
            throw SwiftDataArchiveFailure.unsafePath
        }
    }

    /// duplicateParent shares the caller's existing root lock without a competing open description.
    static func duplicateParent(
        root      : URL,
        descriptor: Int32
    ) throws -> Int32 {
        let duplicate = fcntl(
            descriptor,
            F_DUPFD_CLOEXEC,
            0
        )
        guard duplicate >= 0 else { throw SwiftDataArchiveFailure.unsafePath }
        do {
            try validateHeldRoot(
                root      : root,
                descriptor: duplicate
            )
            return duplicate
        } catch {
            Darwin.close(duplicate)
            throw error
        }
    }

    /// openChild locks a checked private child; only descriptor-relative ENOENT returns nil.
    static func openChild(
        _ parent: Int32,
        name    : String
    ) throws -> Int32? {
        guard let child = try KeyedStorageDirectory.child(
            parent,
            name: name
        ) else { return nil }
        guard flock(
            child,
            LOCK_EX | LOCK_NB
        ) == 0 else {
            Darwin.close(child)
            throw SwiftDataArchiveFailure.unsafePath
        }
        return child
    }

    /// knownChildBytes preserves known entry and non-directory length without following unsafe targets.
    static func knownChildBytes(
        _ parent: Int32,
        name    : String
    ) -> Int {
        var info = stat()
        guard fstatat(
            parent,
            name,
            &info,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else { return 0 }
        guard info.st_mode & S_IFMT != S_IFDIR else { return entryBytes }
        guard info.st_size >= 0, info.st_size <= Int.max - entryBytes else { return Int.max }
        return entryBytes + Int(info.st_size)
    }

    /// inventory continues past unknown safe entries and never follows a symlink or device.
    static func inventory(
        root          : URL,
        descriptor    : Int32,
        fileInspection: any SwiftDataArchiveFileInspecting = NativeSwiftDataArchiveFileInspection()
    ) -> SwiftDataArchiveInventory {
        var scan = Scan()
        do {
            try validateHeldRoot(
                root      : root,
                descriptor: descriptor
            )
            try inspect(
                descriptor    : descriptor,
                depth         : 0,
                fileInspection: fileInspection,
                scan          : &scan
            )
            try validateHeldRoot(
                root      : root,
                descriptor: descriptor
            )
        } catch {
            scan.isComplete       = false
            scan.hasUnsafeEntries = true
        }
        return SwiftDataArchiveInventory(
            bytes            : scan.bytes,
            isComplete       : scan.isComplete,
            hasUnsafeEntries : scan.hasUnsafeEntries,
            hasUnknownEntries: scan.hasUnknownEntries
        )
    }

    /// inspect streams at most 4096 entries and eight directory levels without retaining names.
    private static func inspect(
        descriptor    : Int32,
        depth         : Int,
        fileInspection: any SwiftDataArchiveFileInspecting,
        scan          : inout Scan
    ) throws {
        guard depth <= maximumDepth else { throw SwiftDataArchiveFailure.unsafePath }
        try KeyedStorageDirectory.entries(
            descriptor,
            maximumCount    : maximumEntries,
            maximumNameBytes: 255
        ) { name in
            guard scan.entries < maximumEntries else { throw SwiftDataArchiveFailure.unsafePath }
            scan.entries += 1
            var information = stat()
            guard fstatat(
                descriptor,
                name,
                &information,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else { throw SwiftDataArchiveFailure.unsafePath }
            let kind  = information.st_mode & S_IFMT
            let known = depth == 0 && managedNames.contains(name)
            if !known { scan.hasUnknownEntries = true }
            try add(
                entryBytes,
                scan: &scan
            )
            if kind == S_IFDIR {
                scan.hasUnknownEntries = true
                guard let child = try KeyedStorageDirectory.child(
                    descriptor,
                    name: name
                ) else { throw SwiftDataArchiveFailure.unsafePath }
                defer { Darwin.close(child) }
                try inspect(
                    descriptor    : child,
                    depth         : depth + 1,
                    fileInspection: fileInspection,
                    scan          : &scan
                )
            } else {
                guard information.st_size >= 0,
                      information.st_size <= Int.max else { throw SwiftDataArchiveFailure.unsafePath }
                try add(
                    Int(information.st_size),
                    scan: &scan
                )
                guard kind == S_IFREG else {
                    scan.hasUnsafeEntries = true
                    return
                }
                do {
                    guard let (file, identity) = try fileInspection.openFile(
                        descriptor,
                        name: name
                    ) else { throw SwiftDataArchiveFailure.unsafePath }
                    defer { Darwin.close(file) }
                    // A racing replacement/growth invalidates the scan, but its larger checked
                    // length is still known retained storage and cannot be discarded with the error.
                    if identity.size > information.st_size {
                        try add(
                            identity.size - Int(information.st_size),
                            scan: &scan
                        )
                    }
                    guard identity.device == information.st_dev,
                          identity.inode == information.st_ino,
                          identity.size == information.st_size else {
                        throw SwiftDataArchiveFailure.unsafePath
                    }
                } catch {
                    scan.hasUnsafeEntries = true
                }
            }
        }
    }

    /// add rejects unrepresentable inventories without inventing a smaller complete observation.
    private static func add(
        _ bytes: Int,
        scan   : inout Scan
    ) throws {
        let result = scan.bytes.addingReportingOverflow(bytes)
        guard !result.overflow else { throw SwiftDataArchiveFailure.accounting }
        scan.bytes = result.partialValue
    }

    /// prepareStore creates only an absent private database after the caller prepays growth.
    /// Existing files are neither truncated nor chmod-repaired. Any created file stays inventoried.
    static func prepareStore(
        root      : URL,
        descriptor: Int32
    ) throws {
        try validateHeldRoot(
            root      : root,
            descriptor: descriptor
        )
        if let (file, _) = try KeyedStorageDirectory.file(
            descriptor,
            name   : "archive.store",
            maximum: Int.max
        ) {
            Darwin.close(file)
            return
        }
        let file = openat(
            descriptor,
            "archive.store",
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard file >= 0 else { throw SwiftDataArchiveFailure.unsafePath }
        defer { Darwin.close(file) }
        guard fchmod(
            file,
            0o600
        ) == 0 else { throw SwiftDataArchiveFailure.unsafePath }
    }
}

/// SwiftDataArchiveCommitChecking revalidates the held root at the actual save boundary.
/// Failure-injection implementations must forward the real check before a deliberate failure.
protocol SwiftDataArchiveCommitChecking: Sendable {
    func validateCommit(
        root      : URL,
        descriptor: Int32
    ) throws
}

/// NativeSwiftDataArchiveCommitCheck rejects root replacement before committing changed models.
struct NativeSwiftDataArchiveCommitCheck: SwiftDataArchiveCommitChecking {
    func validateCommit(
        root      : URL,
        descriptor: Int32
    ) throws {
        try SwiftDataArchiveDirectory.validateHeldRoot(
            root      : root,
            descriptor: descriptor
        )
    }
}


/// SwiftDataArchiveFileInspecting confines deterministic scan races to a checked real file open.
/// Returned descriptors and identities must come from the existing safe filesystem helper.
protocol SwiftDataArchiveFileInspecting: Sendable {
    func openFile(
        _ descriptor: Int32,
        name        : String
    ) throws -> (Int32, KeyedStorageDirectory.FileIdentity)?
}

/// NativeSwiftDataArchiveFileInspection measures regular files without a quota-truncated inventory.
struct NativeSwiftDataArchiveFileInspection: SwiftDataArchiveFileInspecting {
    func openFile(
        _ descriptor: Int32,
        name        : String
    ) throws -> (Int32, KeyedStorageDirectory.FileIdentity)? {
        try KeyedStorageDirectory.file(
            descriptor,
            name   : name,
            maximum: Int.max
        )
    }
}

/// SwiftDataArchiveDirectoryCreating confines provisioning to the admitted synchronous mkdir boundary.
protocol SwiftDataArchiveDirectoryCreating: Sendable {
    func createDirectory(
        parentDescriptor: Int32,
        name            : String
    ) throws
}

/// NativeSwiftDataArchiveDirectoryCreation forwards strict provisioning to the existing secure helper.
struct NativeSwiftDataArchiveDirectoryCreation: SwiftDataArchiveDirectoryCreating {
    func createDirectory(
        parentDescriptor: Int32,
        name            : String
    ) throws {
        try KeyedStorageDirectory.createDirectory(
            parentDescriptor,
            name: name
        )
    }
}
