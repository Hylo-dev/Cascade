//
//  NotchCalibrationPanel.swift
//  CascadeKit
//

import AppKit
import QuartzCore

/// NotchCalibrationPanel accepts arrows only while this explicit calibration
/// surface owns keyboard focus. Three red guides span the entire active display.
@MainActor
final class NotchCalibrationPanel: NSPanel, NotchCalibrationPresenting {
    var onStep: ((CGFloat, CGFloat) -> Void)?
    var onFinish: ((Bool) -> Void)?

    private let canvas = CalibrationCanvas(frame: .zero)
    private var isCalibrating = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = canvas
        title = "Regola dimensioni del notch"
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Closing a menu can briefly return focus to the previous app. Keep
        // this utility panel visible and preserve the draft through that handoff.
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        canvas.onStep = { [weak self] width, height in self?.onStep?(width, height) }
        canvas.onFinish = { [weak self] save in self?.onFinish?(save) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(on display: ActiveDisplay, size: CGSize) {
        isCalibrating = true
        setFrame(display.frame, display: true)
        canvas.frame = CGRect(origin: .zero, size: display.frame.size)
        canvas.scale = display.backingScale
        canvas.update(size: size)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(self)
    }

    func update(size: CGSize) { canvas.update(size: size) }
    func update(geometry: NotchGeometry) { canvas.update(geometry: geometry) }

    func hide() {
        isCalibrating = false
        orderOut(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        guard isCalibrating, event.type == .keyDown else {
            super.sendEvent(event)
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 5 : 1
        switch event.keyCode {
        case 123: onStep?(-step, 0)
        case 124: onStep?(step, 0)
        case 125: onStep?(0, step)
        case 126: onStep?(0, -step)
        case 36, 76: onFinish?(true)
        case 53: onFinish?(false)
        default: super.sendEvent(event)
        }
    }
}
