//
//  NotchLiveActivity.swift
//  CascadeKit
//

import SwiftUI

/// NotchLiveActivity describes an ongoing user-relevant task with a beginning
/// and an end. Publish at an expected time, expose an opt-out and call
/// `NotchEngine.endActivity(id:)` when the task ends. Re-publish lifetime
/// changes even while its views are hidden.
@MainActor
public protocol NotchLiveActivity: NotchActivity {

    var lifetime: NotchActivityLifetime { get }

    /// Only ongoing tasks can supply expanded content. Status notices never
    /// enter this presentation, including when the person hovers over one.
    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView

    /// Relative relevance within 0...1. Prefer an aggregate per source to many
    /// separate activities. Relevance never adds sounds or haptics.
    var relevanceScore: Double { get }

    /// Whether the activity has an expanded presentation at all. One that does not, a status
    /// such as a running assertion, is never selected as the opened notch's content: neither
    /// when the notch opens nor when the person clicks its compact presentation, which fall
    /// back to the widgets as if there were no activity. Only the compact and minimal
    /// presentations remain, so `makeExpandedView` is not asked for content.
    var hasExpandedPresentation: Bool { get }
}

public extension NotchLiveActivity {

    var relevanceScore: Double { 0.5 }

    var hasExpandedPresentation: Bool { true }
}
