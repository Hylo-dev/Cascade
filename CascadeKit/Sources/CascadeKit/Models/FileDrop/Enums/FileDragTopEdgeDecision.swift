//
//  FileDragTopEdgeDecision.swift
//  CascadeKit
//

import CoreGraphics

nonisolated enum FileDragTopEdgeDecision: Equatable, Sendable {

    case pass
    case move(to: CGPoint)
    case stop
}
