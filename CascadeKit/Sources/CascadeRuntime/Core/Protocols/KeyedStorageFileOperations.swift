//
//  KeyedStorageFileOperations.swift
//  CascadeKit
//

/// KeyedStorageFileOperations isolates only synchronous failure-prone syscalls for deterministic tests.
/// Successful test operations must forward to the real held-descriptor implementation.
protocol KeyedStorageFileOperations: Sendable {

    func write(
        _ descriptor: Int32,
        bytes       : UnsafeRawBufferPointer
    ) -> Int

    func unlink(
        _ directory: Int32,
        name       : String
    ) -> Int32

    func syncDirectory(_ descriptor: Int32) -> Int32
}
