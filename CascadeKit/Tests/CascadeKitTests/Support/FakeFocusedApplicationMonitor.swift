//
//  FakeFocusedApplicationMonitor.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

@MainActor
final class FakeFocusedApplicationMonitor: FocusedApplicationMonitoring {

    var onChange   : (() -> Void)?
    var application: FocusedApplication?

    init(application: FocusedApplication?) {
        self.application = application
    }

    var frontmostApplication: FocusedApplication? {
        application
    }

    func start() {}

    func stop() {}
}
