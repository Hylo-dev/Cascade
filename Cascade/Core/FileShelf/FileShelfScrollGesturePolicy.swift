//
//  FileShelfScrollGesturePolicy.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct FileShelfScrollGesturePolicy {
    private static let threshold: CGFloat = 4
    private var distance = CGSize.zero
    private var isTracking = false
    private var didNavigate = false

    static func exceedsIntentThreshold(_ distance: CGSize) -> Bool {
        hypot(distance.width, distance.height) >= threshold
    }

    mutating func navigation(
        delta                    : CGSize,
        phase                    : NSEvent.Phase,
        momentumPhase            : NSEvent.Phase,
        behavior                 : FileShelfScrollNavigation,
        isAtHorizontalLeadingEdge _: Bool
    ) -> FileShelfScrollDirection? {
        guard momentumPhase.isEmpty else { return nil }
        if phase.contains(.cancelled) {
            reset()
            return nil
        }
        if phase.contains(.began) {
            reset()
            isTracking = true
        } else if phase.isEmpty {
            if !isTracking { isTracking = true }
        } else if !isTracking {
            // A renderer replacement can receive the tail of the gesture that
            // opened it. Wait for fresh fingers instead of closing immediately.
            return nil
        }

        defer {
            if phase.contains(.ended) { reset() }
        }
        guard !didNavigate else { return nil }
        distance.width += delta.width
        distance.height += delta.height
        guard Self.exceedsIntentThreshold(distance) else { return nil }

        let direction: FileShelfScrollDirection
        if abs(distance.width) >= abs(distance.height) {
            direction = distance.width >= 0 ? .horizontalPositive : .horizontalNegative
        } else {
            direction = distance.height >= 0 ? .verticalPositive : .verticalNegative
        }
        switch behavior {
        case .open:
            break
        case .close(let expectedDirection):
            // Horizontal gestures browse one item at a time. The controller
            // decides whether a backward gesture at the first item closes.
            guard direction.isHorizontal || direction == expectedDirection else { return nil }
        }
        didNavigate = true
        return direction
    }

    private mutating func reset() {
        distance = .zero
        isTracking = false
        didNavigate = false
    }
}
