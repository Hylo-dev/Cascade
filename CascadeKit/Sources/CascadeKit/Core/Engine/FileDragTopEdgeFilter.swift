//
//  FileDragTopEdgeFilter.swift
//  CascadeKit
//

import AppKit
import CoreGraphics

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

    mutating func process(
        _ type     : CGEventType,
        at location: CGPoint
    ) -> FileDragTopEdgeDecision {
        if type == .leftMouseUp {
            geometry = nil
            return .stop
        }
        guard type == .leftMouseDragged, let geometry else { return .pass }

        let clamped = geometry.clamped(location)
        return clamped == location ? .pass : .move(to: clamped)
    }
}
