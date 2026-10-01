//
//  KeyedFileFaults.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

/// KeyedFileFaults forwards real successful syscalls and injects only narrowly classified failures.
final class KeyedFileFaults: KeyedStorageFileOperations, @unchecked Sendable {

    private let lock                  = NSLock()
    private var unlinkFailure         = false
    private var directoryFailure      = false
    private var writeFailure          = false
    private var shortWrites           = false
    private var disappearancePath    : URL?
    private var directoryFailureCount = 0
    private let real                  = POSIXKeyedStorageFileOperations()

    func set(
        unlink   : Bool = false,
        directory: Bool = false,
        write    : Bool = false,
        short    : Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }

        unlinkFailure         = unlink
        directoryFailure      = directory
        writeFailure          = write
        shortWrites           = short
        disappearancePath     = nil
        directoryFailureCount = 0
    }

    func write(
        _ descriptor: Int32,
        bytes       : UnsafeRawBufferPointer
    ) -> Int {
        lock.lock()
        let fails = writeFailure
        let short = shortWrites
        lock.unlock()

        if fails {
            errno = EIO
            return -1
        }

        if short {
            return real.write(descriptor, bytes: UnsafeRawBufferPointer(rebasing: bytes.prefix(7)))
        }

        return real.write(descriptor, bytes: bytes)
    }

    func unlink(
        _ directory: Int32,
        name       : String
    ) -> Int32 {
        lock.lock()
        let fails = unlinkFailure
        lock.unlock()

        if fails {
            errno = EIO
            return -1
        }

        return real.unlink(directory, name: name)
    }

    /// failDirectorySync targets a real visibility transition, not ancestor setup or stage admission.
    func failDirectorySync(afterDisappearanceOf path: URL) {
        lock.lock()
        defer { lock.unlock() }

        disappearancePath     = path
        directoryFailureCount = 0
    }

    var injectedDirectoryFailures: Int {
        lock.lock()
        defer { lock.unlock() }

        return directoryFailureCount
    }

    func syncDirectory(_ descriptor: Int32) -> Int32 {
        lock.lock()
        let fails =
            directoryFailure
            || disappearancePath.map { !FileManager.default.fileExists(atPath: $0.path) } == true
        if fails { directoryFailureCount += 1 }
        lock.unlock()

        if fails {
            errno = EIO
            return -1
        }

        return real.syncDirectory(descriptor)
    }
}
