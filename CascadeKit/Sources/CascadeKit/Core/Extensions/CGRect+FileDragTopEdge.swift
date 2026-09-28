//
//  CGRect+FileDragTopEdge.swift
//  CascadeKit
//

import CoreGraphics

nonisolated extension CGRect {

    var isFiniteAndPositive: Bool {
        [minX, minY, maxX, maxY, width, height].allSatisfy(\.isFinite)
            && width > 0 && height > 0
    }
}
