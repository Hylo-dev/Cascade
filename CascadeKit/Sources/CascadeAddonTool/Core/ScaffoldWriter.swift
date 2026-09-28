//
//  ScaffoldWriter.swift
//  CascadeKit
//

import Darwin
import Foundation

enum ScaffoldWriter {
    /// publish prepares all output under an exclusively created sibling directory.
    /// Pinned descriptors avoid following output symlinks or reopening moved parents.
    /// Cleanup is nonrecursive and checks recorded identities before unlinking. These
    /// separate syscalls are best-effort protection, not isolation from another
    /// process with the same user’s authority to mutate staging entries.
    static func publish(files: [ScaffoldFile], to destination: URL) throws {
        let name = destination.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != "..", !name.contains("\0") else {
            throw ScaffoldError("Destination must name a new directory under an existing parent.")
        }
        let parent = open(destination.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NONBLOCK)
        guard parent >= 0 else { throw ScaffoldError("Destination parent must already exist and be accessible.") }
        defer { close(parent) }
        let stagingName = ".cascade-addon-\(UUID().uuidString)"
        guard mkdirat(parent, stagingName, 0o700) == 0 else { throw ScaffoldError("Cannot create exclusive staging directory.") }
        let staging = openat(parent, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        // If the created name was raced, do not remove anything we cannot identify.
        guard staging >= 0 else { throw ScaffoldError("Cannot open owned staging directory.") }
        var stagingInfo = stat()
        guard fstat(staging, &stagingInfo) == 0 else {
            close(staging)
            throw ScaffoldError("Cannot inspect staging directory.")
        }
        var owned: [OwnedEntry] = [OwnedEntry(parent: parent, name: stagingName, descriptor: staging, info: stagingInfo, directory: true)]
        var published = false
        defer {
            if !published {
                for entry in owned.reversed() { entry.removeIfStillOwned() }
            }
            for entry in owned { close(entry.descriptor) }
        }
        var directories: [String: Int32] = ["": staging]
        for file in files {
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
                throw ScaffoldError("Invalid scaffold output path.")
            }
            var relative = "", directory = staging
            for component in components.dropLast() {
                relative = relative.isEmpty ? component : relative + "/" + component
                if let existing = directories[relative] { directory = existing; continue }
                guard mkdirat(directory, component, 0o700) == 0 else { throw ScaffoldError("Cannot create scaffold subdirectory.") }
                let child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw ScaffoldError("Cannot open scaffold subdirectory.") }
                var info = stat()
                guard fstat(child, &info) == 0 else { close(child); throw ScaffoldError("Cannot inspect scaffold subdirectory.") }
                owned.append(OwnedEntry(parent: directory, name: component, descriptor: child, info: info, directory: true))
                directories[relative] = child
                directory = child
            }
            guard let filename = components.last else { throw ScaffoldError("Missing scaffold filename.") }
            let descriptor = openat(directory, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw ScaffoldError("Cannot exclusively create scaffold file.") }
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { close(descriptor); throw ScaffoldError("Cannot inspect scaffold file.") }
            owned.append(OwnedEntry(parent: directory, name: filename, descriptor: descriptor, info: info, directory: false))
            try file.data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw ScaffoldError("Cannot write complete scaffold file.") }
                    offset += count
                }
            }
        }
        guard owned.allSatisfy({ $0.isStillOwned }) else { throw ScaffoldError("Staging contents changed before publication.") }
        // Never replace a file, an empty directory or even a dangling symlink.
        guard renameatx_np(parent, stagingName, parent, name, UInt32(RENAME_EXCL)) == 0 else {
            throw ScaffoldError("Destination already exists or exclusive publication failed; no destination was overwritten.")
        }
        published = true
    }

    private struct OwnedEntry {
        let parent: Int32
        let name: String
        let descriptor: Int32
        let info: stat
        let directory: Bool

        var isStillOwned: Bool {
            var current = stat()
            return fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0
                && current.st_dev == info.st_dev && current.st_ino == info.st_ino
                && current.st_mode & mode_t(S_IFMT) == info.st_mode & mode_t(S_IFMT)
        }

        func removeIfStillOwned() {
            if isStillOwned { _ = unlinkat(parent, name, directory ? AT_REMOVEDIR : 0) }
        }
    }
}
