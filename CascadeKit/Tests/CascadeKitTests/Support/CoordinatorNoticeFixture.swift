//
//  CoordinatorNoticeFixture.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class CoordinatorNoticeFixture: NotchTransientNotice {

    let id                : String
    let sourceID           = "coordinator-notice-tests"
    let contentRevision   : UInt64 = 0
    let privacy           : NotchActivityPrivacy = .standard
    let displayDuration   : TimeInterval = 5
    let accessibilityLabel = "Coordinator notice"

    private(set) var activations = 0

    init(id: String) { self.id = id }

    func activate(in context: LiveActivityContext) { activations += 1 }

    func suspend() {}

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(EmptyView())
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(EmptyView())
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(EmptyView())
    }
}
