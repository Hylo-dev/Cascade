//
//  FileDragTopEdgeGuard.swift
//  CascadeKit
//

import AppKit
import CoreGraphics
import OSLog

/// FileDragTopEdgeGuard is a short-lived public Quartz event filter. Its
/// owner may call `start` after AppKit validates a native offer or from a
/// fresh, stable regular-file hint. The hint only protects UI routing;
/// `NSDraggingInfo` remains the sole drop admission authority.
@MainActor
final class FileDragTopEdgeGuard: FileDragTopEdgeGuardOperating {

    enum Availability: Equatable {

        case inactive
        case active
        case unavailable
    }

    private static let logger        = Logger(subsystem: "hylo.Cascade", category: "FileDrop")
    private static let leaseDuration: TimeInterval = 30

    private enum StopReason: String {

        case external
        case invalidGeometry
        case leaseExpired
        case mouseUp
        case restart
        case tapStateLost
        case unavailable
    }

    private var port      : CFMachPort?
    private var source    : CFRunLoopSource?
    private var leaseTimer: Timer?
    private var filter    : FileDragTopEdgeFilter?

    private var loggedActive         = false
    private var loggedUnavailable    = false
    private var diagnosticsAreActive = false
    private var dragEventCount       = 0
    private var clampCount           = 0

    private(set) var availability: Availability = .inactive

    @discardableResult
    func start(
        region: CGRect,
        screen: CGRect
    ) -> Bool {
        teardown(reason: .restart)

        guard let primaryScreen = NSScreen.screens.first?.frame,
              let geometry = FileDragTopEdgeGeometry(
                region       : region,
                screen       : screen,
                primaryScreen: primaryScreen
              )
        else {
            availability = .inactive
            return false
        }

        filter = FileDragTopEdgeFilter(geometry: geometry)

        let mask = (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap             : .cgSessionEventTap,
            place           : .headInsertEventTap,
            options         : .defaultTap,
            eventsOfInterest: mask,
            callback        : { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }

                return MainActor.assumeIsolated {
                    let owner = Unmanaged<FileDragTopEdgeGuard>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    return owner.handle(type, event: event)
                }
            },
            userInfo        : Unmanaged.passUnretained(self).toOpaque()
        ) else {
            markUnavailable()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            markUnavailable()
            return false
        }

        self.port   = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        CGEvent.tapEnable(tap: port, enable: true)
        guard CGEvent.tapIsEnabled(tap: port) else {
            markUnavailable()
            return false
        }

        availability         = .active
        diagnosticsAreActive = true
        renewLease()

        if !loggedActive {
            loggedActive = true
            Self.logger.info("phase=edgeGuard state=active")
        }
        return true
    }

    func update(
        region: CGRect,
        screen: CGRect
    ) {
        guard availability == .active,
              let primaryScreen = NSScreen.screens.first?.frame,
              let geometry = FileDragTopEdgeGeometry(
                region       : region,
                screen       : screen,
                primaryScreen: primaryScreen
              )
        else {
            stop(reason: .invalidGeometry)
            return
        }

        filter?.update(geometry)
        renewLease()
    }

    func stop() {
        stop(reason: .external)
    }

    private func stop(reason: StopReason) {
        teardown(reason: reason)
        if availability != .unavailable { availability = .inactive }
    }

    private func handle(
        _ type: CGEventType,
        event : CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableIfActive()
            return Unmanaged.passUnretained(event)
        }
        guard var filter else { return Unmanaged.passUnretained(event) }

        if type == .leftMouseDragged {
            dragEventCount += 1
            if dragEventCount == 1 {
                Self.logger.notice("phase=edgeGuard state=firstDrag")
            }
        }

        let decision = filter.process(type, at: event.location)
        self.filter  = filter

        switch decision {
            case .pass:
                break

            case .move(let location):
                clampCount += 1
                if clampCount == 1 {
                    Self.logger.notice("phase=edgeGuard state=firstClamp")
                }
                event.location = location

            case .stop:
                stop(reason: .mouseUp)
        }

        return Unmanaged.passUnretained(event)
    }

    private func reenableIfActive() {
        guard availability == .active, filter != nil, let port else {
            stop(reason: .tapStateLost)
            return
        }

        CGEvent.tapEnable(tap: port, enable: true)
        if !CGEvent.tapIsEnabled(tap: port) { markUnavailable() }
    }

    private func renewLease() {
        leaseTimer?.invalidate()

        let timer = Timer(timeInterval: Self.leaseDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop(reason: .leaseExpired) }
        }
        leaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func markUnavailable() {
        teardown(reason: .unavailable)
        availability = .unavailable

        if !loggedUnavailable {
            loggedUnavailable = true
            Self.logger.error("phase=edgeGuard error=eventTapUnavailable")
        }
    }

    private func teardown(reason: StopReason) {
        if diagnosticsAreActive {
            Self.logger.notice(
                "phase=edgeGuard state=stopped reason=\(reason.rawValue, privacy: .public) dragEvents=\(self.dragEventCount) clamps=\(self.clampCount)"
            )
        }

        diagnosticsAreActive = false
        dragEventCount       = 0
        clampCount           = 0

        leaseTimer?.invalidate()
        leaseTimer = nil

        filter?.disarm()
        filter = nil

        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port   = nil
    }

    deinit {
        leaseTimer?.invalidate()
        if let source { CFRunLoopSourceInvalidate(source) }
        if let port { CFMachPortInvalidate(port) }
    }
}
