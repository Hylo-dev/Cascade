//
//  ControllerActivityFixture.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ControllerActivityFixture: NotchLiveActivity {

    let id                   : String
    let sourceID             : String
    let contentRevision      : UInt64
    let privacy              : NotchActivityPrivacy
    let lifetime             : NotchActivityLifetime
    let relevanceScore       : Double
    let expandedContentHeight: CGFloat

    private(set) var activations                = 0
    private(set) var suspensions                = 0
    private(set) var factoryRanBeforeActivation = false
    private(set) var accessibilityLabelReads    = 0
    private(set) var contentURLReads            = 0
    private(set) var compactLeadingContexts    : [NotchActivityViewContext] = []
    private(set) var compactTrailingContexts   : [NotchActivityViewContext] = []
    private(set) var minimalContexts           : [NotchActivityViewContext] = []
    private(set) var expandedContexts          : [NotchActivityViewContext] = []

    var contentFactoryCount: Int {
        compactLeadingContexts.count
            + compactTrailingContexts.count
            + minimalContexts.count
            + expandedContexts.count
    }

    var accessibilityLabel: String {
        accessibilityLabelReads += 1
        return "Activity \(id)"
    }

    var contentURL: URL? {
        contentURLReads += 1
        return URL(string: "cascade://activity/\(id)")
    }

    init(
        id                   : String,
        sourceID             : String = "controller-tests",
        contentRevision      : UInt64 = 0,
        privacy              : NotchActivityPrivacy = .standard,
        lifetime             : NotchActivityLifetime = NotchActivityLifetime(duration: 60),
        relevanceScore       : Double = 0.5,
        expandedContentHeight: CGFloat = 88
    ) {
        self.id                    = id
        self.sourceID              = sourceID
        self.contentRevision       = contentRevision
        self.privacy               = privacy
        self.lifetime              = lifetime
        self.relevanceScore        = relevanceScore
        self.expandedContentHeight = expandedContentHeight
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        compactLeadingContexts.append(context)
        return AnyView(Text(id))
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        compactTrailingContexts.append(context)
        return AnyView(Text(id))
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        minimalContexts.append(context)
        return AnyView(Text(id))
    }

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        recordFactoryActivationOrder()
        expandedContexts.append(context)
        return AnyView(Text(id))
    }

    func activate(in context: LiveActivityContext) { activations += 1 }

    func suspend() { suspensions += 1 }

    private func recordFactoryActivationOrder() {
        if activations <= suspensions { factoryRanBeforeActivation = true }
    }
}
