//
//  ControllerNoticeFixture.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ControllerNoticeFixture: NotchTransientNotice {

    let id                       : String
    let sourceID                 : String
    let contentRevision          : UInt64 = 0
    let privacy                  : NotchActivityPrivacy = .standard
    let displayDuration          : TimeInterval
    let borderAppearance         : NotchBorderAppearance?
    let compactPreferredSideWidth: CGFloat?

    private(set) var activations            = 0
    private(set) var expandedFactoryCount   = 0
    private(set) var compactLeadingContexts: [NotchActivityViewContext] = []

    var accessibilityLabel: String { "Notice \(id)" }

    init(
        id                       : String,
        sourceID                 : String = "controller-tests",
        displayDuration          : TimeInterval = 4,
        borderAppearance         : NotchBorderAppearance? = nil,
        compactPreferredSideWidth: CGFloat? = nil
    ) {
        self.id                        = id
        self.sourceID                  = sourceID
        self.displayDuration           = displayDuration
        self.borderAppearance          = borderAppearance
        self.compactPreferredSideWidth = compactPreferredSideWidth
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        compactLeadingContexts.append(context)
        return AnyView(Text(id))
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(Text(id))
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(Text(id))
    }

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        expandedFactoryCount += 1
        return AnyView(Text(id))
    }

    func activate(in context: LiveActivityContext) { activations += 1 }
}
