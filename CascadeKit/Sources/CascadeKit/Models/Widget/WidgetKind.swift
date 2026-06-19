//
//  WidgetKind.swift
//  CascadeKit
//

import Foundation

/// WidgetKind identifies a widget *type* (not an instance). While each placed
/// widget has its own unique `WidgetIdentifier`, the kind is what persistence
/// stores and what a factory uses to recreate the right widget on load — many
/// instances can share one kind.
public nonisolated struct WidgetKind: Hashable, Sendable {

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
