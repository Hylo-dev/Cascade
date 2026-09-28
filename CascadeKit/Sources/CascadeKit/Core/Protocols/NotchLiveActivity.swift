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
}

public extension NotchLiveActivity {

    var relevanceScore: Double { 0.5 }
}
