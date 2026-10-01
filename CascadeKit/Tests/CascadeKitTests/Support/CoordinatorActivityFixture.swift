//
//  CoordinatorActivityFixture.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class CoordinatorActivityFixture: NotchLiveActivity {
    let id: String
    let sourceID: String
    let contentRevision: UInt64 = 0
    let privacy: NotchActivityPrivacy = .standard
    let lifetime = NotchActivityLifetime(duration: 60)
    let expandedContentHeight: CGFloat = 40
    let accessibilityLabel = "Coordinator activity"
    private(set) var activations = 0
    private(set) var suspensions = 0
    private(set) var factoryCount = 0
    private(set) var factoryRanBeforeActivation = false

    var onActivate: (() -> Void)?
    var onCompactLeadingFactory: (() -> Void)?
    var activeCount: Int { activations - suspensions }

    init(id: String, sourceID: String = "coordinator-tests") {
        self.id = id
        self.sourceID = sourceID
    }
    func activate(in context: LiveActivityContext) {
        activations += 1
        onActivate?()
    }
    func suspend() { suspensions += 1 }
    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        onCompactLeadingFactory?()
        factoryCount += 1
        if activations == 0 { factoryRanBeforeActivation = true }
        return AnyView(EmptyView())
    }
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
}
