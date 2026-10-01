//
//  RecordingCalibrationPresenter.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

@MainActor
final class RecordingCalibrationPresenter: NotchCalibrationPresenting {

    var onStep   : ((CGFloat, CGFloat) -> Void)?
    var onFinish : ((Bool) -> Void)?
    var size     : CGSize?
    var geometry : NotchGeometry?
    var display  : ActiveDisplay?
    var hideCount = 0

    func show(
        on display: ActiveDisplay,
        size      : CGSize
    ) {
        self.display = display
        self.size    = size
    }

    func update(size: CGSize) { self.size = size }

    func update(geometry: NotchGeometry) { self.geometry = geometry }

    func hide() { hideCount += 1 }
}
