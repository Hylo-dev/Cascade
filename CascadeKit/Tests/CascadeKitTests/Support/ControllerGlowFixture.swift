//
//  ControllerGlowFixture.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ControllerGlowFixture: NotchLiveActivity {
    let id = "glow-layout-probe"
    let sourceID = "controller-tests"
    let contentRevision: UInt64 = 0
    let privacy: NotchActivityPrivacy = .standard
    let lifetime = NotchActivityLifetime(duration: 60)
    let expandedContentHeight: CGFloat = 150
    let accessibilityLabel = "Glow layout probe"

    func activate(in context: LiveActivityContext) {}
    func suspend() {}
    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { AnyView(EmptyView()) }
    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(Color.clear
            .frame(width: context.availableSize.width, height: context.availableSize.height)
            .background { Color.red.padding(-8) })
    }
}
