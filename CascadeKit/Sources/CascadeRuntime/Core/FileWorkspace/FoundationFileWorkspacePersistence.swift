//
//  FoundationFileWorkspacePersistence.swift
//  CascadeKit
//

import Darwin
import Foundation

/// FoundationFileWorkspacePersistence replaces one manifest atomically inside a host-owned directory.
struct FoundationFileWorkspacePersistence: FileWorkspacePersisting {
    private static let maximumManifestBytes = 10 * 1_024 * 1_024

    let directory: URL

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    func load() async throws -> Data? {
        try FileWorkspacePath.validatePrivateDirectory(directory)
        let url = directory.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try FileWorkspacePath.validateRegularFile(url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= Self.maximumManifestBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func save(_ data: Data) async throws {
        guard data.count <= Self.maximumManifestBytes else {
            throw FileWorkspacePersistenceFailure.notCommitted
        }
        do { try FileWorkspacePath.validatePrivateDirectory(directory) }
        catch { throw FileWorkspacePersistenceFailure.notCommitted }
        let root = Darwin.open(
            directory.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard root >= 0 else { throw FileWorkspacePersistenceFailure.notCommitted }
        defer { Darwin.close(root) }
        var existing = stat()
        if fstatat(root, "manifest.json", &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            guard existing.st_mode & S_IFMT == S_IFREG, existing.st_uid == getuid() else {
                throw FileWorkspacePersistenceFailure.notCommitted
            }
        } else if errno != ENOENT {
            throw FileWorkspacePersistenceFailure.notCommitted
        }

        let staging = ".manifest-\(UUID().uuidString).tmp"
        let descriptor = openat(
            root,
            staging,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw FileWorkspacePersistenceFailure.notCommitted }
        var renamed = false
        defer {
            Darwin.close(descriptor)
            if !renamed { _ = unlinkat(root, staging, 0) }
        }
        do {
            try data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        bytes.count - offset
                    )
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw FileWorkspacePersistenceFailure.notCommitted }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else {
                throw FileWorkspacePersistenceFailure.notCommitted
            }
            guard renameat(root, staging, root, "manifest.json") == 0 else {
                throw FileWorkspacePersistenceFailure.notCommitted
            }
            renamed = true
            guard fsync(root) == 0 else { throw FileWorkspacePersistenceFailure.commitUncertain }
        } catch FileWorkspacePersistenceFailure.commitUncertain {
            throw FileWorkspacePersistenceFailure.commitUncertain
        } catch {
            throw renamed
                ? FileWorkspacePersistenceFailure.commitUncertain
                : FileWorkspacePersistenceFailure.notCommitted
        }
    }
}
