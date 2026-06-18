//
//  NotchRegion.swift
//  CascadeKit
//

import Foundation

/// NotchRegion is where a widget asks to live inside the notch.
///
/// A widget declares a single preferred region; the host honors it against the
/// current `NotchState`, activating the widget only while that region is open.
/// This enum is the bridge between the widget layer and the OptionSet state.
public nonisolated enum NotchRegion: String, CaseIterable, Sendable {

    case leading  = "leading"
    case trailing = "trailing"
    case expanded = "expanded"

    /// The notch state in which this region becomes visible. The expanded
    /// region needs both sides open; a side region needs only its own side.
    public var requiredState: NotchState {
        switch self {
            case .leading : .leading
            case .trailing: .trailing
            case .expanded: .open
        }
    }
}
