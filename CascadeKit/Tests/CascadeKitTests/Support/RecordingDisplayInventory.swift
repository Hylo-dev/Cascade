//
//  RecordingDisplayInventory.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingDisplayInventory: DisplayInventoryProviding {
    var displays: [DisplayInventoryEntry] { entries }
    var onChange: (() -> Void)?
    var entries : [DisplayInventoryEntry]
    private(set) var startCount = 0
    private(set) var stopCount  = 0

    init(entries: [DisplayInventoryEntry]) {
        self.entries = entries
    }

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func sendChange() { onChange?() }
}
