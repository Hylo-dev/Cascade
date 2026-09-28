//
//  DisplayInventoryProviding.swift
//  CascadeKit
//

import AppKit
import ColorSync

/// DisplayInventoryProviding supplies event-driven snapshots of the logical
/// desktop surfaces connected to the current session.
@MainActor
protocol DisplayInventoryProviding: AnyObject {
    var displays: [DisplayInventoryEntry] { get }
    var onChange: (() -> Void)? { get set }

    func start()
    func stop()
}
