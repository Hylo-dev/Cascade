//
//  KeyedAncestorSyncFaults.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

/// KeyedAncestorSyncFaults records actual directory identities and fails only the chosen managed parent.
/// Successful calls always reach the real POSIX adapter; no successful fsync is fabricated.
final class KeyedAncestorSyncFaults: KeyedStorageFileOperations, @unchecked Sendable {

    struct Identity: Equatable, Sendable {

        let device: dev_t
        let inode : ino_t
    }

    struct Event: Sendable {

        let identity : Identity
        let succeeded: Bool
    }

    private let lock = NSLock()
    private let real = POSIXKeyedStorageFileOperations()

    private var failingParent: URL?
    private var recorded     : [Event] = []

    init(failingParent: URL) { self.failingParent = failingParent }

    func allowSyncs() {
        lock.lock()
        defer { lock.unlock() }

        failingParent = nil
    }

    func events() -> [Event] {
        lock.lock()
        defer { lock.unlock() }

        return recorded
    }

    static func identity(of url: URL) throws -> Identity {
        var info = stat()
        guard fstatat(AT_FDCWD, url.path, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw KeyedStorageFailure.io(errno)
        }

        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    func write(
        _ descriptor: Int32,
        bytes       : UnsafeRawBufferPointer
    ) -> Int {
        real.write(descriptor, bytes: bytes)
    }

    func unlink(
        _ directory: Int32,
        name       : String
    ) -> Int32 {
        real.unlink(directory, name: name)
    }

    func syncDirectory(_ descriptor: Int32) -> Int32 {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return -1 }

        let identity = Identity(device: info.st_dev, inode: info.st_ino)
        lock.lock()
        let target = failingParent
        lock.unlock()

        let mustFail = target.flatMap { try? Self.identity(of: $0) } == identity
        let result: Int32

        if mustFail {
            errno  = EIO
            result = -1
        } else {
            result = real.syncDirectory(descriptor)
        }

        lock.lock()
        recorded.append(Event(identity: identity, succeeded: result == 0))
        lock.unlock()

        return result
    }
}
