//
//  DisplayInventoryScreen.swift
//  CascadeKit
//

import AppKit
import ColorSync

/// DisplayInventoryScreen is the AppKit-ordered snapshot/name pair captured
/// before persistent identity and mirror topology are resolved.
///
/// Keeping this source separate from both resolvers lets tests exercise the
/// same mapping used for real NSScreen values instead of supplying finished
/// inventory entries that could hide a broken UUID or mirror lookup.
nonisolated struct DisplayInventoryScreen: Equatable, Sendable {
    let snapshot: ActiveDisplay
    let name    : String

    init(
        snapshot: ActiveDisplay,
        name    : String
    ) {
        self.snapshot = snapshot
        self.name     = name
    }
}
