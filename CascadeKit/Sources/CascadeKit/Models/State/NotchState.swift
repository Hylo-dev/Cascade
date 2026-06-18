//
//  NotchState.swift
//  CascadeKit
//

import Foundation

/// NotchState describes which sides of the notch are currently expanded.
///
/// It is an OptionSet, not a plain enum, because the leading and trailing sides
/// open independently — a widget can claim the left while the right stays shut,
/// exactly like a Dynamic Island. `.closed` is the empty set, so "is anything
/// open?" is a single `isEmpty` check; `.open` composes both side bits. The
/// morph engine reads the set to know how far each side should travel; the
/// widget layer reads it to know which regions are live.
///
/// It is part of the public widget SDK surface (widgets and the host reason
/// about it), so it is `public` and `@frozen`.
@frozen
public nonisolated struct NotchState: OptionSet, Sendable {

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let leading  = NotchState(rawValue: 1 << 0) // Left side expanded.
    public static let trailing = NotchState(rawValue: 1 << 1) // Right side expanded.

    public static let closed: NotchState = []                 // Resting, hugging the notch.
    public static let open  : NotchState = [.leading, .trailing]

    /// Whether the notch is fully at rest, with nothing expanded.
    public var isClosed: Bool { isEmpty }
}
