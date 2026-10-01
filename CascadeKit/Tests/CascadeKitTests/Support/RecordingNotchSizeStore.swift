//
//  RecordingNotchSizeStore.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

@MainActor
final class RecordingNotchSizeStore: NotchSizeStoring {
    var sizes: [CGDirectDisplayID: CGSize] = [:]
    func size(for displayID: CGDirectDisplayID) -> CGSize? { sizes[displayID] }
    func setSize(_ size: CGSize, for displayID: CGDirectDisplayID) { sizes[displayID] = size }
}
