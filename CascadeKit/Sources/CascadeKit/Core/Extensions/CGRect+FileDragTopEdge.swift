//
//  CGRect+FileDragTopEdge.swift
//  CascadeKit
//

import AppKit
import CoreGraphics
import OSLog

nonisolated extension CGRect {
    var isFiniteAndPositive: Bool {
        [minX, minY, maxX, maxY, width, height].allSatisfy(\.isFinite)
            && width > 0 && height > 0
    }
}
