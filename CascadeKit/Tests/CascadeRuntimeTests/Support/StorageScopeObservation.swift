//
//  StorageScopeObservation.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

final class StorageScopeObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var entries = 0
    private var encodings = 0
    var counts: [Int] { lock.withLock { [entries, encodings] } }
    func entered() { lock.withLock { entries += 1 } }
    func encoded() { lock.withLock { encodings += 1 } }
}
