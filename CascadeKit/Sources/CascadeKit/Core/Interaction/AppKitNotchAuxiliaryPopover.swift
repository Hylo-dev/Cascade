//
//  AppKitNotchAuxiliaryPopover.swift
//  CascadeKit
//

import AppKit

/// AppKitNotchAuxiliaryPopover owns exactly one native popover and reads its
/// actual window frame through its content view. The host's full-width window
/// is deliberately never used as a hover rectangle.
@MainActor
final class AppKitNotchAuxiliaryPopover: NotchAuxiliaryPopoverHosting {

    private weak var anchor: NSView?
    private weak var host  : NotchHostView?
    private let preferredEdge: NSRectEdge
    private(set) var popover  : NSPopover?

    init(
        anchor       : NSView,
        host         : NotchHostView,
        preferredEdge: NSRectEdge
    ) {
        self.anchor        = anchor
        self.host          = host
        self.preferredEdge = preferredEdge
    }

    var anchorFrame: CGRect? {
        guard let anchor,
              let host,
              let window = anchor.window,
              window === host.window,
              window.isVisible,
              !anchor.isHiddenOrHasHiddenAncestor,
              anchor.isDescendant(of: host),
              !anchor.visibleRect.isEmpty else { return nil }
        return window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    }

    var popoverFrame: CGRect? {
        guard let popover,
              popover.isShown,
              let window = popover.contentViewController?.view.window,
              window.isVisible else { return nil }
        return window.frame
    }

    func containsNotch(_ point: CGPoint) -> Bool {
        guard let host, let window = host.window else { return false }
        return host.containsInteractivePoint(host.convert(window.convertPoint(fromScreen: point), from: nil))
    }

    func show(
        _ content: NSViewController,
        delegate : any NSPopoverDelegate
    ) -> Bool {
        guard let anchor, anchorFrame != nil else { return false }
        content.view.layoutSubtreeIfNeeded()
        let preferred = content.preferredContentSize
        let fitting   = content.view.fittingSize
        let size = CGSize(
            width : preferred.width > 0 ? preferred.width : fitting.width,
            height: preferred.height > 0 ? preferred.height : fitting.height
        )
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return false }
        let popover                   = NSPopover()
        self.popover                  = popover
        popover.delegate              = delegate
        popover.behavior              = .applicationDefined
        popover.animates              = false
        popover.appearance            = anchor.effectiveAppearance
        popover.contentViewController = content
        popover.contentSize           = size
        popover.show(
            relativeTo   : anchor.bounds,
            of           : anchor,
            preferredEdge: preferredEdge
        )
        return popover.isShown
    }

    func close() {
        let previous = popover
        popover      = nil
        previous?.delegate = nil
        previous?.close()
        previous?.contentViewController = nil
    }
}
