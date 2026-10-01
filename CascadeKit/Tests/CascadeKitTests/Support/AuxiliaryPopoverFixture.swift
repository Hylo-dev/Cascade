//
//  AuxiliaryPopoverFixture.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

/// AuxiliaryPopoverFixture keeps geometry and ownership tests independent of
/// the WindowServer, so no real output routing or visible windows are needed.
@MainActor
final class AuxiliaryPopoverFixture: NotchAuxiliaryPopoverHosting {
    var anchorFrame: CGRect? = CGRect(x: 210, y: 125, width: 20, height: 20)
    var frame               = CGRect(x: 150, y: 0, width: 180, height: 80)
    var canShow             = true
    var showCount           = 0
    var closeCount          = 0
    var content             : NSViewController?
    var popover             : NSPopover? { nil }
    var popoverFrame        : CGRect? { content == nil ? nil : frame }

    func containsNotch(_ point: CGPoint) -> Bool {
        CGRect(x: 0, y: 100, width: 300, height: 100).contains(point)
    }

    func show(
        _ content: NSViewController,
        delegate : any NSPopoverDelegate
    ) -> Bool {
        showCount += 1
        self.content = content
        return canShow
    }

    func close() {
        closeCount += 1
        content = nil
    }

    func waitUntilShown() async {
        for _ in 0..<100 where showCount == 0 { await Task.yield() }
        #expect(showCount == 1)
    }
}
