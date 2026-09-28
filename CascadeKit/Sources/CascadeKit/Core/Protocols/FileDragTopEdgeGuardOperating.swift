//
//  FileDragTopEdgeGuardOperating.swift
//  CascadeKit
//

import CoreGraphics

@MainActor
protocol FileDragTopEdgeGuardOperating: AnyObject {

    var availability: FileDragTopEdgeGuard.Availability { get }

    @discardableResult
    func start(
        region: CGRect,
        screen: CGRect
    ) -> Bool

    func update(
        region: CGRect,
        screen: CGRect
    )

    func stop()
}
