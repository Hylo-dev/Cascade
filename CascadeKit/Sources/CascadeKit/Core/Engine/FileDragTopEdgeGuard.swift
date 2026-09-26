import AppKit
import CoreGraphics
import OSLog

@MainActor
protocol FileDragTopEdgeGuardOperating: AnyObject {
    var availability: FileDragTopEdgeGuard.Availability { get }
    @discardableResult
    func start(region: CGRect, screen: CGRect) -> Bool
    func update(region: CGRect, screen: CGRect)
    func stop()
}

nonisolated struct FileDragTopEdgeGeometry: Equatable, Sendable {
    private static let edgeTolerance: CGFloat = 0.5
    private static let inset: CGFloat = 2

    let horizontalRange: ClosedRange<CGFloat>
    let topEdgeY: CGFloat

    /// Converts AppKit global coordinates using the first (principal) screen's
    /// top edge. Display-topology changes therefore require `update` or `start`.
    init?(region: CGRect, screen: CGRect, primaryScreen: CGRect) {
        guard region.isFiniteAndPositive,
              screen.isFiniteAndPositive,
              primaryScreen.isFiniteAndPositive,
              region.minY <= screen.maxY,
              region.maxY >= screen.maxY else { return nil }

        let minX = max(region.minX, screen.minX) - primaryScreen.minX
        let maxX = min(region.maxX, screen.maxX) - primaryScreen.minX
        guard minX < maxX else { return nil }

        horizontalRange = minX...maxX
        topEdgeY = primaryScreen.maxY - screen.maxY
    }

    func clamped(_ location: CGPoint) -> CGPoint {
        guard horizontalRange.contains(location.x),
              abs(location.y - topEdgeY) <= Self.edgeTolerance else { return location }
        return CGPoint(x: location.x, y: topEdgeY + Self.inset)
    }
}

nonisolated enum FileDragTopEdgeDecision: Equatable, Sendable {
    case pass
    case move(to: CGPoint)
    case stop
}

nonisolated struct FileDragTopEdgeFilter: Sendable {
    private var geometry: FileDragTopEdgeGeometry?

    init(geometry: FileDragTopEdgeGeometry) {
        self.geometry = geometry
    }

    mutating func update(_ geometry: FileDragTopEdgeGeometry) {
        self.geometry = geometry
    }

    mutating func disarm() {
        geometry = nil
    }

    mutating func process(_ type: CGEventType, at location: CGPoint) -> FileDragTopEdgeDecision {
        if type == .leftMouseUp {
            geometry = nil
            return .stop
        }
        guard type == .leftMouseDragged, let geometry else { return .pass }
        let clamped = geometry.clamped(location)
        return clamped == location ? .pass : .move(to: clamped)
    }
}

private nonisolated extension CGRect {
    var isFiniteAndPositive: Bool {
        [minX, minY, maxX, maxY, width, height].allSatisfy(\.isFinite)
            && width > 0 && height > 0
    }
}

/// A short-lived public Quartz event filter. Its owner may call `start` after
/// AppKit validates a native offer or from a fresh, stable regular-file hint.
/// The hint only protects UI routing; `NSDraggingInfo` remains the sole drop
/// admission authority.
@MainActor
final class FileDragTopEdgeGuard: FileDragTopEdgeGuardOperating {
    enum Availability: Equatable {
        case inactive
        case active
        case unavailable
    }

    private static let logger = Logger(subsystem: "hylo.Cascade", category: "FileDrop")
    private static let leaseDuration: TimeInterval = 30

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var leaseTimer: Timer?
    private var filter: FileDragTopEdgeFilter?
    private var loggedActive = false
    private var loggedUnavailable = false

    private(set) var availability: Availability = .inactive

    @discardableResult
    func start(region: CGRect, screen: CGRect) -> Bool {
        teardown()
        guard let primaryScreen = NSScreen.screens.first?.frame,
              let geometry = FileDragTopEdgeGeometry(
                region: region,
                screen: screen,
                primaryScreen: primaryScreen
              ) else {
            availability = .inactive
            return false
        }

        filter = FileDragTopEdgeFilter(geometry: geometry)
        let mask = (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<FileDragTopEdgeGuard>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    return owner.handle(type, event: event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            markUnavailable()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            markUnavailable()
            return false
        }

        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard CGEvent.tapIsEnabled(tap: port) else {
            markUnavailable()
            return false
        }

        availability = .active
        renewLease()
        if !loggedActive {
            loggedActive = true
            Self.logger.info("phase=edgeGuard state=active")
        }
        return true
    }

    func update(region: CGRect, screen: CGRect) {
        guard availability == .active,
              let primaryScreen = NSScreen.screens.first?.frame,
              let geometry = FileDragTopEdgeGeometry(
                region: region,
                screen: screen,
                primaryScreen: primaryScreen
              ) else {
            stop()
            return
        }
        filter?.update(geometry)
        renewLease()
    }

    func stop() {
        teardown()
        if availability != .unavailable { availability = .inactive }
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableIfActive()
            return Unmanaged.passUnretained(event)
        }
        guard var filter else { return Unmanaged.passUnretained(event) }
        let decision = filter.process(type, at: event.location)
        self.filter = filter
        switch decision {
        case .pass:
            break
        case .move(let location):
            event.location = location
        case .stop:
            stop()
        }
        return Unmanaged.passUnretained(event)
    }

    private func reenableIfActive() {
        guard availability == .active, filter != nil, let port else {
            stop()
            return
        }
        CGEvent.tapEnable(tap: port, enable: true)
        if !CGEvent.tapIsEnabled(tap: port) { markUnavailable() }
    }

    private func renewLease() {
        leaseTimer?.invalidate()
        let timer = Timer(timeInterval: Self.leaseDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        leaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func markUnavailable() {
        teardown()
        availability = .unavailable
        if !loggedUnavailable {
            loggedUnavailable = true
            Self.logger.error("phase=edgeGuard error=eventTapUnavailable")
        }
    }

    private func teardown() {
        leaseTimer?.invalidate()
        leaseTimer = nil
        filter?.disarm()
        filter = nil
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }

    deinit {
        leaseTimer?.invalidate()
        if let source { CFRunLoopSourceInvalidate(source) }
        if let port { CFMachPortInvalidate(port) }
    }
}
