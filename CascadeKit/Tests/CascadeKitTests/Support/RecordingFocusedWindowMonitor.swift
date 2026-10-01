//
//  RecordingFocusedWindowMonitor.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingFocusedWindowMonitor: FocusedWindowMonitoring {

    var onChange: ((CGRect?) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount  = 0

    func start() { startCount += 1 }

    func stop() { stopCount += 1 }

    func refresh() {}

    func send(frame: CGRect?) { onChange?(frame) }
}
