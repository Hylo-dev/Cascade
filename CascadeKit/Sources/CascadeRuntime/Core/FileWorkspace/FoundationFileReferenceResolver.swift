//
//  FoundationFileReferenceResolver.swift
//  CascadeKit
//

import Darwin
import Foundation

/// FoundationFileReferenceResolver uses security-scoped bookmarks and descriptor identity.
struct FoundationFileReferenceResolver: FileReferenceResolving {
    func createReference(to url: URL) async throws -> FileReferenceLease {
        let canonical = url.standardizedFileURL
        return try Self.lease(url: canonical) { checkedURL, identity in
            let bookmark = try Self.bookmark(for: checkedURL)
            try Self.verify(bookmark, identifies: identity)
            return bookmark
        }
    }

    func resolve(_ bookmark: Data) async throws -> FileReferenceLease {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options              : [.withSecurityScope, .withoutUI],
            relativeTo           : nil,
            bookmarkDataIsStale  : &stale
        )
        return try Self.lease(url: url) { checkedURL, identity in
            guard stale else { return bookmark }
            let refreshed = try Self.bookmark(for: checkedURL)
            try Self.verify(refreshed, identifies: identity)
            return refreshed
        }
    }

    private static func lease(
        url         : URL,
        makeBookmark: (URL, FileReferenceIdentity) throws -> Data
    ) throws -> FileReferenceLease {
        let scoped = url.startAccessingSecurityScopedResource()
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw CocoaError(.fileReadNoPermission)
        }
        do {
            let identity = try Self.identity(descriptor)
            let bookmark = try makeBookmark(url, identity)
            return FileReferenceLease(
                url       : url,
                bookmark  : bookmark,
                identity  : identity,
                descriptor: descriptor,
                scoped    : scoped
            )
        } catch {
            Darwin.close(descriptor)
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options                       : [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo                    : nil
        )
    }

    /// verify closes the pathname race by resolving the finished bookmark while the source
    /// descriptor is still held and requiring the same device, inode and generation.
    private static func verify(
        _ bookmark: Data,
        identifies expected: FileReferenceIdentity
    ) throws {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options              : [.withSecurityScope, .withoutUI],
            relativeTo           : nil,
            bookmarkDataIsStale  : &stale
        )
        guard !stale else { throw CocoaError(.fileReadUnknown) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { Darwin.close(descriptor) }
        guard try identity(descriptor) == expected else { throw CocoaError(.fileReadUnknown) }
    }

    private static func identity(_ descriptor: Int32) throws -> FileReferenceIdentity {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return FileReferenceIdentity(
            device    : UInt64(info.st_dev),
            inode     : UInt64(info.st_ino),
            generation: UInt64(info.st_gen)
        )
    }
}
