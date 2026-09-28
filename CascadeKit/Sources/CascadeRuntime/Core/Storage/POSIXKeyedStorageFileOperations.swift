//
//  POSIXKeyedStorageFileOperations.swift
//  CascadeKit
//

import Darwin
import Foundation

/// POSIXKeyedStorageFileOperations forwards bounded I/O to the kernel without asynchronous handoffs.
struct POSIXKeyedStorageFileOperations: KeyedStorageFileOperations {
    func write(
        _ descriptor : Int32,
        bytes        : UnsafeRawBufferPointer
    ) -> Int {
        Darwin.write(
            descriptor,
            bytes.baseAddress,
            bytes.count
        )
    }

    func unlink(
        _ directory : Int32,
        name        : String
    ) -> Int32 {
        unlinkat(
            directory,
            name,
            0
        )
    }
    func syncDirectory(_ descriptor: Int32) -> Int32 { fsync(descriptor) }
}
