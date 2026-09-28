//
//  NotchAuxiliaryPopoverHosting.swift
//  CascadeKit
//

import AppKit

/// NotchAuxiliaryPopoverHosting separates pointer policy from AppKit placement
/// and lifetime, allowing focused tests without opening windows or routing audio.
@MainActor
protocol NotchAuxiliaryPopoverHosting: AnyObject {
    var anchorFrame : CGRect? { get }
    var popoverFrame: CGRect? { get }
    var popover     : NSPopover? { get }

    func containsNotch(_ point: CGPoint) -> Bool
    func show(
        _ content: NSViewController,
        delegate : any NSPopoverDelegate
    ) -> Bool
    func close()
}
