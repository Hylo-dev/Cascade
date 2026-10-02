//
//  ScreenshotKeyTap.swift
//  Cascade
//

import CoreGraphics
import Foundation

/// ScreenshotKeyTap wraps Quartz's native event stream and reuses the existing
/// run-loop owner. Suppression is synchronous on that thread; opening the notch
/// is asynchronous, so a busy UI cannot stall the rest of the keyboard.
@MainActor
final class ScreenshotKeyTap: ScreenshotKeyTapping {

    /// CallbackContext belongs to one installation and outlives its last
    /// callback via EventTapThread's exit closure. Retired callbacks can only
    /// touch their own gate, never the replacement tap's mutable state.
    nonisolated private final class CallbackContext: Sendable {

        let gate = ScreenshotKeyGate()
        let onShortcut: @Sendable () -> Void
        let onCancel  : @Sendable () -> Void
        let onDisabled: @Sendable () -> Void

        init(
            onShortcut: @escaping @Sendable () -> Void,
            onCancel  : @escaping @Sendable () -> Void,
            onDisabled: @escaping @Sendable () -> Void
        ) {
            self.onShortcut = onShortcut
            self.onCancel   = onCancel
            self.onDisabled = onDisabled
        }
    }

    private var port      : CFMachPort?
    private var thread    : EventTapThread?
    private var context   : CallbackContext?
    private var generation: UInt64 = 0
    private var onShortcut: (@MainActor () -> Void)?
    private var onCancel  : (@MainActor () -> Void)?
    private var onDisabled: (@MainActor () -> Void)?
    private var cancellationEnabled = false

    var isActive: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start(
        shortcuts : ScreenshotShortcuts,
        onShortcut: @escaping @MainActor () -> Void,
        onCancel  : @escaping @MainActor () -> Void,
        onDisabled: @escaping @MainActor () -> Void
    ) -> Bool {
        stop()

        let installation = generation
        let context = CallbackContext(
            onShortcut: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == installation else { return }

                    self.onShortcut?()
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == installation else { return }

                    self.onCancel?()
                }
            },
            onDisabled: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == installation else { return }

                    self.onDisabled?()
                }
            }
        )
        let keyDown = CGEventMask(1) << CGEventType.keyDown.rawValue
        let keyUp   = CGEventMask(1) << CGEventType.keyUp.rawValue
        guard let port = CGEvent.tapCreate(
            tap             : .cgSessionEventTap,
            place           : .headInsertEventTap,
            options         : .defaultTap,
            eventsOfInterest: keyDown | keyUp,
            callback        : Self.callback,
            userInfo        : Unmanaged.passUnretained(context).toOpaque()
        ),
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return false }

        self.port       = port
        self.context    = context
        self.onShortcut = onShortcut
        self.onCancel   = onCancel
        self.onDisabled = onDisabled
        context.gate.update(shortcuts: shortcuts)
        context.gate.setCancellationEnabled(cancellationEnabled)

        let thread = EventTapThread()
        thread.start(
            name  : "Cascade.ScreenshotKeys",
            source: source,
            onExit: { [context] in _ = context }
        )
        self.thread = thread
        CGEvent.tapEnable(tap: port, enable: true)
        guard isActive else {
            stop()
            return false
        }

        return true
    }

    /// callback's unretained context is kept alive by the run-loop exit closure.
    /// stop invalidates the port before ending that loop. Only fresh shortcuts
    /// schedule a UI callback; the event itself never leaves its owning thread.
    nonisolated private static let callback: CGEventTapCallBack = { _, type, event, pointer in
        guard let pointer else { return Unmanaged.passUnretained(event) }

        let context = Unmanaged<CallbackContext>.fromOpaque(pointer).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            context.gate.update(shortcuts: nil)
            context.onDisabled()
            return Unmanaged.passUnretained(event)
        }

        switch context.gate.consume(type: type, event: event) {
            case .pass:
                return Unmanaged.passUnretained(event)

            case .suppress:
                return nil

            case .open:
                context.onShortcut()
                return nil

            case .cancel:
                context.onCancel()
                return nil
        }
    }

    func setCancellationEnabled(_ isEnabled: Bool) {
        cancellationEnabled = isEnabled
        context?.gate.setCancellationEnabled(isEnabled)
    }

    func stop() {
        generation &+= 1
        context?.gate.update(shortcuts: nil)
        if let port { CFMachPortInvalidate(port) }
        port = nil
        thread?.stop()
        thread = nil
        context = nil
        onShortcut = nil
        onCancel = nil
        onDisabled = nil
    }
}
