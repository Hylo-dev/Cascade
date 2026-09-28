//
//  FileDragTopEdgeGuardOperating.swift
//  CascadeKit
//

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
