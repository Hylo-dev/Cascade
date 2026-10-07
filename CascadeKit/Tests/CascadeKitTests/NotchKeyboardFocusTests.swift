import AppKit
import Testing
@testable import CascadeKit

@MainActor
struct NotchKeyboardFocusTests {
    @Test
    func overlayAcceptsKeysOnlyAfterAnExplicitKeyboardTargetBecomesResponder() {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 440, height: 144))
        let target = KeyboardTarget(frame: content.bounds)
        content.addSubview(target)
        let panel = NotchPanel(contentView: content)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.makeFirstResponder(target))
        #expect(panel.canBecomeKey)
        #expect(panel.makeFirstResponder(nil))
        #expect(!panel.canBecomeKey)
    }
}

@MainActor
private final class KeyboardTarget: NSView, NotchKeyboardFocusTarget {
    override var acceptsFirstResponder: Bool { true }
}
