//
//  MutableDisplayResolver.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class MutableDisplayResolver: ActiveDisplayResolving {
    var display: ActiveDisplay

    init(display: ActiveDisplay) {
        self.display = display
    }

    func resolveActiveDisplay() -> ActiveDisplay? {
        display
    }
}
