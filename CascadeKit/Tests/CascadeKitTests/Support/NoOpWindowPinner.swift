//
//  NoOpWindowPinner.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NoOpWindowPinner: WindowPinning {

    func pin(_ window: NSWindow) {}
}
