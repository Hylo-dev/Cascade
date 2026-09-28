//
//  ActiveDisplayResolving.swift
//  CascadeKit
//

import Foundation

/// ActiveDisplayResolving is the legacy single-surface display bridge.
///
/// It remains intact until the display coordinator owns snapshots in task 4,
/// preserving the current controller contract while focused-window selection is
/// kept in `FocusedDisplayResolver` and out of this AppKit adapter.
protocol ActiveDisplayResolving {

    /// resolveActiveDisplay returns the pointer screen, then the main screen.
    /// It never consults application focus or Accessibility.
    func resolveActiveDisplay() -> ActiveDisplay?
}
