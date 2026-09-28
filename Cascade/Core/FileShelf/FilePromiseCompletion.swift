//
//  FilePromiseCompletion.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

nonisolated final class FilePromiseCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (((any Error)?) -> Void)?

    init(_ completion: @escaping ((any Error)?) -> Void) {
        self.completion = completion
    }

    func call(_ error: (any Error)?) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(error)
    }
}
