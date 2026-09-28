//
//  FileReferenceLease.swift
//  CascadeKit
//

import Darwin
import Foundation

/// FileReferenceLease keeps both the checked descriptor and security scope alive for a read.
/// Callers must retain the lease until their final byte read rather than retaining its URL alone.
final class FileReferenceLease: @unchecked Sendable {
    let url              : URL
    let bookmark         : Data
    let identity         : FileReferenceIdentity
    let descriptor: Int32

    private let scoped: Bool
    private let lock = NSLock()
    private var isClosed = false

    init(
        url       : URL,
        bookmark  : Data,
        identity  : FileReferenceIdentity,
        descriptor: Int32,
        scoped    : Bool
    ) {
        self.url        = url
        self.bookmark   = bookmark
        self.identity   = identity
        self.descriptor = descriptor
        self.scoped     = scoped
    }

    deinit { close() }

    func close() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        lock.unlock()
        Darwin.close(descriptor)
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
}
