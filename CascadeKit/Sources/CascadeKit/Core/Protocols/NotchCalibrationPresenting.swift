//
//  NotchCalibrationPresenting.swift
//  CascadeKit
//

import CoreGraphics

/// NotchCalibrationPresenting provides a temporary keyboard surface and guides.
/// Finishing hides every guide and releases keyboard focus; no global key tap
/// or additional system permission is needed.
@MainActor
protocol NotchCalibrationPresenting: AnyObject {
    var onStep: ((CGFloat, CGFloat) -> Void)? { get set }
    var onFinish: ((Bool) -> Void)? { get set }
    func show(on display: ActiveDisplay, size: CGSize)
    func update(size: CGSize)
    func update(geometry: NotchGeometry)
    func hide()
}
