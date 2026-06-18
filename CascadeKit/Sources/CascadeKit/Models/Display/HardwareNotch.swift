//
//  HardwareNotch.swift
//  CascadeKit
//

import CoreGraphics

/// HardwareNotch holds the physical cut-out metrics of a display.
///
/// Only the built-in display of recent MacBooks has a notch; everywhere else
/// this is `.absent`. We capture it as a plain value (not a live NSScreen
/// query) so the rest of the engine can reason about geometry without touching
/// AppKit, and so a snapshot can cross to a background context safely.
nonisolated struct HardwareNotch: Equatable, Sendable {

    let isPresent: Bool
    let size     : CGSize // The cut-out's width/height; `.zero` when absent.

    /// The notch on a display that has none.
    static let absent = HardwareNotch(
        isPresent: false,
        size     : .zero
    )
}
