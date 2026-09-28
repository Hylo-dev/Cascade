//
//  DisplayExpansionTrigger.swift
//  CascadeKit
//

import AppKit
import OSLog

/// DisplayExpansionTrigger describes why a local surface wants ownership.
/// Hover requests are cancellable while explicit invocations remain valid until
/// the surface withdraws them or its display leaves the inventory.
enum DisplayExpansionTrigger: Equatable {
    case hover
    case click
    case accessibility
    case settings
    case spotlight
    case calibration
    case popover
    case drag
}
