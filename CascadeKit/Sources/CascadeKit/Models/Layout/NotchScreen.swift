//
//  NotchScreen.swift
//  CascadeKit
//

import Foundation

/// NotchScreen is one "page" of the notch — the home-screen-style screens the
/// top-leading slider pages through.
///
/// It holds only the *arrangement*: which widget sits where, keyed by the
/// widget's id. The widget instances themselves live once in the workspace's
/// `widgets` dictionary and are referenced here by id, so a widget shown on
/// several screens is never duplicated in memory. A dictionary (not an array)
/// because the arrangement is looked up by id (drag, hit-test, removal) and the
/// on-screen place is the `GridPosition`, not insertion order.
nonisolated struct NotchScreen: Identifiable, Sendable {

    let id: Int
    var arrangement: [WidgetIdentifier: WidgetPlacement]

    init(
        id         : Int,
        arrangement: [WidgetIdentifier: WidgetPlacement] = [:]
    ) {
        self.id          = id
        self.arrangement = arrangement
    }
}
