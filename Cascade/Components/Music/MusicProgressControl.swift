//
//  MusicProgressControl.swift
//  Cascade
//

import AppKit
import SwiftUI

/// MusicProgressControl previews continuously during mouse tracking and commits
/// once on release. Scroll previews commit at finger release or after a wheel
/// burst settles; momentum is ignored. Keyboard and accessibility stay native.
@MainActor
final class MusicProgressControl: NSSlider {
    var onPreview: (TimeInterval) -> Void = { _ in }
    var onCommit : (TimeInterval) -> Void = { _ in }
    var onCancel : () -> Void = {}
    private(set) var isScrubbing = false
    private var didChangeDuringDrag = false
    private var dragPreview: ((TimeInterval) -> Void)?
    private struct ScrollGesture {
        let startValue: Double
        let preview: (TimeInterval) -> Void
        let commit: (TimeInterval) -> Void
        let cancel: () -> Void
    }
    private var scrollGesture: ScrollGesture?
    private var scrollIdleTask: Task<Void, Never>?

    var trackIdentity: [String] = [] {
        didSet {
            if oldValue != trackIdentity { finishScroll(commit: false, deferCancellation: true) }
        }
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { finishScroll(commit: false, deferCancellation: true) }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell         = MusicProgressCell()
        sliderType   = .linear
        isVertical   = false
        isContinuous = true
        controlSize  = .small
        target       = self
        action       = #selector(valueChanged)
        setAccessibilityLabel("Avanzamento brano")
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        finishScroll(commit: false)
        // Keep the displayed track's callbacks for the entire gesture. A
        // metadata update must not redirect an old drag to the next track.
        let commit = onCommit
        let cancel = onCancel
        dragPreview = onPreview
        isScrubbing = true
        didChangeDuringDrag = false
        defer {
            isScrubbing = false
            dragPreview = nil
            if didChangeDuringDrag && isEnabled { commit(doubleValue) }
            else { cancel() }
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, minValue.isFinite, maxValue.isFinite, maxValue > minValue,
              !isScrubbing || scrollGesture != nil else { return }
        if event.phase.contains(.cancelled) {
            finishScroll(commit: false)
            return
        }
        // Finger release owns the seek. Inertial events must not start a new
        // gesture or send another command after the user has chosen a position.
        guard event.momentumPhase.isEmpty else {
            finishScroll(commit: true)
            return
        }
        let x = event.scrollingDeltaX
        let y = event.scrollingDeltaY
        let delta = abs(x) > abs(y) ? -x : y
        if delta.isFinite && delta != 0 {
            let step = event.hasPreciseScrollingDeltas ? 0.2 : 5.0
            let value = min(maxValue, max(minValue, doubleValue + delta * step))
            if value != doubleValue {
                if scrollGesture == nil {
                    scrollGesture = ScrollGesture(startValue: doubleValue, preview: onPreview,
                                                  commit: onCommit, cancel: onCancel)
                    isScrubbing = true
                }
                doubleValue = value
                needsDisplay = true
                scrollGesture?.preview(value)
            }
        }
        if event.phase.contains(.ended) {
            finishScroll(commit: true)
        } else if event.phase.isEmpty && scrollGesture != nil {
            // Conventional wheels have no gesture phases. Coalesce their
            // ticks without flooding Music/Spotify with AppleEvents.
            scrollIdleTask?.cancel()
            scrollIdleTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                self?.finishScroll(commit: true)
            }
        } else {
            // A finger can rest on the trackpad for longer than the wheel
            // debounce. Only its explicit end should commit that gesture.
            scrollIdleTask?.cancel()
            scrollIdleTask = nil
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishScroll(commit: false, deferCancellation: true) }
        super.viewWillMove(toWindow: newWindow)
    }

    private func finishScroll(commit: Bool, deferCancellation: Bool = false) {
        scrollIdleTask?.cancel()
        scrollIdleTask = nil
        guard let gesture = scrollGesture else { return }
        scrollGesture = nil
        isScrubbing = false
        let value = doubleValue
        if commit && isEnabled && value != gesture.startValue {
            gesture.commit(value)
        } else {
            doubleValue = gesture.startValue
            needsDisplay = true
            if deferCancellation {
                // Identity/enabled/window updates may originate in a SwiftUI
                // render pass; notify its state after that pass has completed.
                Task { @MainActor in gesture.cancel() }
            } else {
                gesture.cancel()
            }
        }
    }

    @objc
    private func valueChanged() {
        guard isEnabled else { return }
        let value = doubleValue
        if let gesture = scrollGesture {
            gesture.preview(value)
            finishScroll(commit: true)
            return
        }
        let commit = onCommit
        (dragPreview ?? onPreview)(value)
        if isScrubbing {
            didChangeDuringDrag = true
        } else {
            commit(value)
        }
    }
}

/// MusicProgressCell clips a flat-ended fill to one rounded track. Omitting
/// knob drawing leaves AppKit's tracking, keyboard and accessibility intact.
@MainActor
private final class MusicProgressCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {}

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(
            x     : rect.minX,
            y     : rect.midY - 3.5,
            width : rect.width,
            height: 7
        )
        let outline = NSBezierPath(roundedRect: track, xRadius: 3.5, yRadius: 3.5)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        outline.addClip()
        NSColor(white: 0.14, alpha: 1).setFill()
        outline.fill()

        let fraction = maxValue > minValue
            ? min(1, max(0, (doubleValue - minValue) / (maxValue - minValue)))
            : 0
        NSColor(white: 0.62, alpha: isEnabled ? 1 : 0.5).setFill()
        NSRect(
            x     : track.minX,
            y     : track.minY,
            width : track.width * fraction,
            height: track.height
        ).fill()
    }
}
