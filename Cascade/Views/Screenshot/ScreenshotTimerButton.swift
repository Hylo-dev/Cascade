//
//  ScreenshotTimerButton.swift
//  Cascade
//

import AppKit
import SwiftUI

/// ScreenshotTimerButton confines wheel handling to the timer's native control.
/// No global event monitor or idle timer survives the page; fractional trackpad
/// input accumulates without publishing UI state on every wheel event.
struct ScreenshotTimerButton: NSViewRepresentable {

    let seconds: Int
    let onCycle: @MainActor () -> Void
    let onStep : @MainActor (Int) -> Void

    func makeNSView(context: Context) -> ScreenshotTimerControl {
        ScreenshotTimerControl(frame: .zero)
    }

    func updateNSView(_ view: ScreenshotTimerControl, context: Context) {
        view.title = "\(seconds) s"
        view.onCycle = onCycle
        view.onStep  = onStep
        view.toolTip = String(localized: "Delay: \(seconds) s. Scroll to adjust; click for 0, 3, 5 or 10 seconds.")
        view.setAccessibilityLabel(String(localized: "Capture Timer"))
        view.setAccessibilityValue("\(seconds) s")
        view.setAccessibilityIdentifier("screenshot.timer")
    }
}

/// ScreenshotTimerControl uses AppKit's button semantics for keyboard and
/// accessibility. Momentum cannot continue increasing a delay after release.
final class ScreenshotTimerControl: NSButton {

    var onCycle: (@MainActor () -> Void)?
    var onStep : (@MainActor (Int) -> Void)?
    private var wheelRemainder: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        font = .systemFont(ofSize: 11, weight: .medium)
        image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        imagePosition = .imageLeading
        contentTintColor = .white
        target = self
        action = #selector(cycle)
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func cycle() { onCycle?() }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, event.momentumPhase.isEmpty else { return }

        let delta = event.scrollingDeltaY
        guard delta.isFinite, delta != 0 else { return }
        if !event.hasPreciseScrollingDeltas {
            onStep?(delta > 0 ? 1 : -1)
            return
        }
        if event.phase.contains(.began) || delta.sign != wheelRemainder.sign {
            wheelRemainder = 0
        }
        wheelRemainder += delta
        let steps = Int(wheelRemainder / 8)
        if steps != 0 {
            wheelRemainder -= CGFloat(steps) * 8
            onStep?(steps)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { wheelRemainder = 0 }
    }
}
