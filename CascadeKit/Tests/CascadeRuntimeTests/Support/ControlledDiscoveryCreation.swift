//
//  ControlledDiscoveryCreation.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

final class ControlledDiscoveryCreation: SwiftDataArchiveDirectoryCreating, @unchecked Sendable {

    enum Failure: Error {

        case injected
    }

    private let lock  = NSLock()
    private var point: String?

    init(point: String) { self.point = point }

    func createDirectory(
        parentDescriptor: Int32,
        name            : String
    ) throws {
        let selected = lock.withLock {
            let selected = point
            point        = nil
            return selected
        }

        if selected == "throwBefore" { throw Failure.injected }
        if selected == "cancelBefore" {
            withUnsafeCurrentTask { $0?.cancel() }
            try Task.checkCancellation()
        }

        try KeyedStorageDirectory.createDirectory(parentDescriptor, name: name)

        if selected == "cancelAfter" { withUnsafeCurrentTask { $0?.cancel() } }
        if selected == "exists" { throw KeyedStorageFailure.io(EEXIST) }
    }
}
