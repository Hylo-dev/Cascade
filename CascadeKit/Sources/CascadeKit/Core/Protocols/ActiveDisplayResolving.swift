//
//  ActiveDisplayResolving.swift
//  CascadeKit
//

import Foundation

/// ActiveDisplayResolving is the legacy single-surface display bridge.
///
/// It predates the display coordinator, which now owns display snapshots
/// through `DisplayInventory`. The protocol keeps the older single-controller
/// contract intact, while focused-window selection is kept in
/// `FocusedDisplayResolver` and out of this AppKit adapter.
protocol ActiveDisplayResolving {

    /// resolveActiveDisplay returns the pointer screen, then the main screen.
    /// It never consults application focus or Accessibility.
    func resolveActiveDisplay() -> ActiveDisplay?
}
