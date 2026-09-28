//
//  FileDragTopEdgeDecision.swift
//  CascadeKit
//

import AppKit
import CoreGraphics
import OSLog

nonisolated enum FileDragTopEdgeDecision: Equatable, Sendable {
    case pass
    case move(to: CGPoint)
    case stop
}
