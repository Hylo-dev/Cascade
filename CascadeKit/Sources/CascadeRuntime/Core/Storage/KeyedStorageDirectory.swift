//
//  KeyedStorageDirectory.swift
//  CascadeKit
//

import Darwin
import Foundation

/// KeyedStorageDirectory confines all child access to held descriptors with bounded synchronous I/O.
/// Root-only retention costs one descriptor. Deep streaming reconciliation peaks at seven descriptors:
/// root, root iterator, namespace, namespace iterator, class, class iterator and current file.
enum KeyedStorageDirectory {

    /// FileIdentity captures the device, inode and logical length of a checked regular file.
    struct FileIdentity: Equatable {

        let device: dev_t
        let inode : ino_t
        let size  : Int
    }

    /// openRoot walks existing components without following symlinks, then validates and locks the root.
    static func openRoot(_ root: URL) throws -> Int32 {
        let path       = root.path
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard root.isFileURL,
              path.hasPrefix("/"),
              !path.utf8.contains(0),
              !components.isEmpty,
              !components.contains(".."),
              !components.contains(".")
        else { throw KeyedStorageFailure.unsafePath }

        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw KeyedStorageFailure.unsafePath }

        do {
            for component in components {
                let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw KeyedStorageFailure.unsafePath }

                Darwin.close(descriptor)
                descriptor = next
            }
            try validateDirectory(descriptor)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw KeyedStorageFailure.busy }

            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    /// validateDirectory requires a private current-user directory, including absence of special mode bits.
    static func validateDirectory(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(),
              info.st_mode & 0o7777 == 0o700
        else {
            throw KeyedStorageFailure.unsafePath
        }
    }

    /// child opens one private directory relative to its held parent; only ENOENT represents absence.
    static func child(
        _ parent: Int32,
        name    : String
    ) throws -> Int32? {
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw KeyedStorageFailure.unsafePath }

        do { try validateDirectory(descriptor) } catch {
            Darwin.close(descriptor)
            throw error
        }

        return descriptor
    }

    /// createDirectory uses exclusive mkdir after the caller has reserved its metadata.
    static func createDirectory(
        _ parent: Int32,
        name    : String
    ) throws {
        guard mkdirat(parent, name, 0o700) == 0 else { throw KeyedStorageFailure.io(errno) }
    }

    /// file opens a safe regular file without following links or blocking on a FIFO.
    static func file(
        _ parent: Int32,
        name    : String,
        maximum : Int
    ) throws -> (Int32, FileIdentity)? {
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw KeyedStorageFailure.unsafePath }

        do {
            return (descriptor, try identity(descriptor, maximum: maximum))
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    /// identity checks type, owner, mode, link count and bounded fstat length before buffer allocation.
    static func identity(
        _ descriptor: Int32,
        maximum     : Int
    ) throws -> FileIdentity {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1,
              info.st_uid == getuid(),
              info.st_mode & 0o7177 == 0,
              info.st_mode & 0o400 != 0
        else { throw KeyedStorageFailure.unsafePath }
        guard info.st_size >= 0, info.st_size <= maximum else { throw KeyedStorageFailure.oversized }

        return FileIdentity(
            device: info.st_dev,
            inode : info.st_ino,
            size  : Int(info.st_size)
        )
    }

    /// read owns the bounded Data buffer for the duration of read; no pointer escapes its closure.
    static func read(
        _ descriptor: Int32,
        size        : Int
    ) throws -> Data {
        guard size <= KeyedStorageRecord.maximumBytes else { throw KeyedStorageFailure.oversized }

        var bytes = Data(count: size)
        try bytes.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < size {
                guard let base = buffer.baseAddress else { throw KeyedStorageFailure.corrupt }

                let count = Darwin.read(descriptor, base.advanced(by: offset), size - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw KeyedStorageFailure.corrupt }

                offset += count
            }
        }

        return bytes
    }

    /// write fills an exclusively created file with every byte and fsyncs it; the caller records
    /// existence before any possible error.
    static func write(
        _ descriptor: Int32,
        bytes       : Data,
        operations  : any KeyedStorageFileOperations
    ) throws {
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let remaining = UnsafeRawBufferPointer(rebasing: buffer[offset...])
                let count     = operations.write(descriptor, bytes: remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0, count <= remaining.count else { throw KeyedStorageFailure.io(errno) }

                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw KeyedStorageFailure.io(errno) }
    }

    /// entries streams names with bounded count and length before constructing a retained String.
    /// The dirent pointer belongs to readdir and is consumed synchronously before the next call.
    static func entries(
        _ descriptor    : Int32,
        maximumCount    : Int,
        maximumNameBytes: Int,
        isolation       : isolated (any Actor)? = #isolation,
        permitNext      : () throws -> Void = {},
        visit           : (String) throws -> Void
    ) throws {
        // A fresh open file description avoids sharing the retained root's directory offset.
        let scan = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scan >= 0 else { throw KeyedStorageFailure.io(errno) }
        guard let directory = fdopendir(scan) else {
            Darwin.close(scan)
            throw KeyedStorageFailure.io(errno)
        }
        defer { closedir(directory) }

        var count = 0
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw KeyedStorageFailure.io(errno) }
                return
            }

            let length = Int(entry.pointee.d_namlen)
            try withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                try pointer.withMemoryRebound(to: CChar.self, capacity: length + 1) { name in
                    if length == 1, name[0] == 46 { return }
                    if length == 2, name[0] == 46, name[1] == 46 { return }
                    guard count < maximumCount, length <= maximumNameBytes else {
                        throw KeyedStorageFailure.quotaExceeded
                    }

                    try permitNext()
                    count += 1
                    try visit(String(cString: name))
                }
            }
        }
    }

    /// isValueName recognizes only the fixed lowercase SHA-256 filename grammar.
    static func isValueName(_ name: String) -> Bool {
        guard name.utf8.count == 70, name.hasSuffix(".value") else { return false }

        return name.utf8.prefix(64).allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
