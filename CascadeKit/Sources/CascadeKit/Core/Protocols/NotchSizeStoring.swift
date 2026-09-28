//
//  NotchSizeStoring.swift
//  CascadeKit
//

import CoreGraphics
import Foundation

/// NotchSizeStoring separates saved display dimensions from a calibration draft.
@MainActor
protocol NotchSizeStoring: AnyObject {
    func size(for displayID: CGDirectDisplayID) -> CGSize?
    func setSize(_ size: CGSize, for displayID: CGDirectDisplayID)
}
