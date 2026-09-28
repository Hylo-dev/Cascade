//
//  VolumeMediaKeyTap.swift
//  Cascade
//

import AppKit
import CoreGraphics
@preconcurrency import ApplicationServices

/// VolumeMediaKeyTap owns one public Quartz tap on a dedicated run-loop thread.
/// The callback never enters MainActor. The run-loop thread retains this object
/// for the entire raw userInfo lifetime; its port is invalidated before release.
/// The unchecked Sendable seam protects only lifecycle state with its lock.
nonisolated final class VolumeMediaKeyTap: @unchecked Sendable {

    typealias KeyHandler          = @Sendable (VolumeMediaKey, Bool, Bool) -> Bool
    typealias AvailabilityHandler = @Sendable (Bool) -> Void

    private let lock = NSLock()

    private let keyHandler         : KeyHandler
    private let availabilityHandler: AvailabilityHandler

    private var runLoop  : CFRunLoop?
    private var isStopped = false

    // Accessed exclusively by the dedicated tap thread.
    private var activePort: CFMachPort?
    private var recovery   = VolumeTapRecovery()

    init(
        keyHandler         : @escaping KeyHandler,
        availabilityHandler: @escaping AvailabilityHandler
    ) {
        self.keyHandler          = keyHandler
        self.availabilityHandler = availabilityHandler
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name             = "Cascade.VolumeKeys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// stop uses a run-loop block so cancellation before CFRunLoopRun still
    /// terminates the first iteration. It never waits on the UI thread.
    func stop() {
        let activeRunLoop = lock.withLock {
            isStopped = true
            return runLoop
        }

        if let activeRunLoop {
            CFRunLoopPerformBlock(activeRunLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(activeRunLoop)
            }
            CFRunLoopWakeUp(activeRunLoop)
        }
    }

    /// decode copies the public NSEvent auxiliary payload on the tap thread.
    /// The subtype and key values are the public IOKit ev_keymap.h constants.
    static func decode(_ event: CGEvent) -> VolumeMediaKey? {
        guard let nativeEvent = NSEvent(cgEvent: event),
              nativeEvent.type == .systemDefined
        else { return nil }

        return VolumeMediaKey.decode(subtype: nativeEvent.subtype.rawValue, data: nativeEvent.data1)
    }

    private func makePort(at location: CGEventTapLocation) -> CFMachPort? {
        let eventMask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue

        return CGEvent.tapCreate(
            tap             : location,
            place           : .headInsertEventTap,
            options         : .defaultTap,
            eventsOfInterest: eventMask,
            callback        : { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }

                let owner = Unmanaged<VolumeMediaKeyTap>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    owner.handleDisabledTap()
                    return Unmanaged.passUnretained(event)
                }

                guard let key = VolumeMediaKeyTap.decode(event)
                else { return Unmanaged.passUnretained(event) }

                let modifiers = event.flags.intersection(
                    [.maskShift, .maskAlternate, .maskControl, .maskCommand]
                )
                let fineStep = modifiers == [.maskShift, .maskAlternate]
                let eligible = modifiers.isEmpty || fineStep

                return owner.keyHandler(key, eligible, fineStep)
                    ? nil
                    : Unmanaged.passUnretained(event)
            },
            userInfo        : Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func handleDisabledTap() {
        if !lock.withLock({ isStopped }),
           recovery.shouldRetry(
               at           : ProcessInfo.processInfo.systemUptime,
               hasPermission: AXIsProcessTrusted()
           ),
           let activePort {
            CGEvent.tapEnable(tap: activePort, enable: true)
            if CGEvent.tapIsEnabled(tap: activePort) {
                availabilityHandler(true)
                return
            }
        }

        availabilityHandler(false)
        stop()
    }

    private func run() {
        guard !lock.withLock({ isStopped }) else { return }

        // Apple's contract restricts HID-location access. A normal user process
        // can use the session tap when that earlier location is unavailable.
        guard let port = makePort(at: .cghidEventTap) ?? makePort(at: .cgSessionEventTap) else {
            availabilityHandler(false)
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            availabilityHandler(false)
            return
        }

        let activeRunLoop = CFRunLoopGetCurrent()
        let shouldRun     = lock.withLock {
            runLoop = activeRunLoop
            return !isStopped
        }

        if shouldRun {
            activePort = port
            CFRunLoopAddSource(activeRunLoop, source, .defaultMode)
            CGEvent.tapEnable(tap: port, enable: true)

            let enabled = CGEvent.tapIsEnabled(tap: port)
            availabilityHandler(enabled)
            if enabled { CFRunLoopRun() }
            CFRunLoopRemoveSource(activeRunLoop, source, .defaultMode)
        }

        activePort = nil
        CFMachPortInvalidate(port)
        lock.withLock { runLoop = nil }
    }
}
