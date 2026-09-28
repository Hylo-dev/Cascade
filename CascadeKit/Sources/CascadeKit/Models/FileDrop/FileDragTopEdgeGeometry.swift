//
//  FileDragTopEdgeGeometry.swift
//  CascadeKit
//

import AppKit
import CoreGraphics
import OSLog

nonisolated struct FileDragTopEdgeGeometry: Equatable, Sendable {
    private static let edgeTolerance: CGFloat = 0.5
    private static let inset: CGFloat = 2

    let horizontalRange: ClosedRange<CGFloat>
    let topEdgeY: CGFloat

    /// init converts AppKit global coordinates using the first (principal) screen's
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
