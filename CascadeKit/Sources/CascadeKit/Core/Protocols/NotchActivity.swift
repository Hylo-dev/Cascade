//
//  NotchActivity.swift
//  CascadeKit
//

import SwiftUI

/// NotchActivity is the shared presentation contract for a task or brief status
/// notice. This local macOS surface is not an ActivityKit conformance. Show
/// only task information, never promotions. Keep every family recognizable and
/// readable; reserve compact/minimal for a glance and expanded for essential
/// actions. Factories respect the supplied bounds and never start polling or
/// continuous animation.
@MainActor
public protocol NotchActivity: AnyObject {
    var id: String { get }
    var sourceID: String { get }

    /// Change only with displayed content/state. Re-publishing the same instance
    /// and revision leaves its views and deadlines untouched.
    var contentRevision: UInt64 { get }
    var accessibilityLabel: String { get }
    var privacy: NotchActivityPrivacy { get }

    /// Optional contextual rim tint while this activity is visible. Nil inherits
    /// the engine's current status; hidden sensitive content cannot override it.
    var borderAppearance: NotchBorderAppearance? { get }

    /// One relevant destination shared by both compact halves and minimal.
    /// Nil is appropriate when no real destination exists, including previews.
    var contentURL: URL? { get }
    /// Optional outer width of each compact side. The renderer clamps it to
    /// safe display bounds and ignores it when sensitive content is hidden.
    var compactPreferredSideWidth: CGFloat? { get }
    /// Content height excluding the cutout and host margins; bounded by the host.
    var expandedContentHeight: CGFloat { get }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView
    /// Hooks own visible resources only. Publish/end through the engine even
    /// while suspended; a hidden provider must not depend on a visible context.
    func activate(in context: LiveActivityContext)
    func suspend()
}

public extension NotchActivity {
    var borderAppearance: NotchBorderAppearance? { nil }
    var contentURL: URL? { nil }
    var compactPreferredSideWidth: CGFloat? { nil }
    var expandedContentHeight: CGFloat { 88 }
    func activate(in context: LiveActivityContext) {}
    func suspend() {}
}
