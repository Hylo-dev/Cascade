//
//  FileDissolveMask.swift
//  CascadeKit
//

import CascadeContracts
import AppKit
import SwiftUI

/// FileDissolveMask breaks a removed file into 8×8 cells that drop away at
/// staggered thresholds. It is a Shape, one path rebuilt per animation frame:
/// as a Canvas it rendered on the GPU and held ~56 MB of transient graphics
/// memory through every removal, at ~2.5× the CPU.
struct FileDissolveMask: Shape {
    let progress: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = 8
        let rows = 8
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let threshold = CGFloat((column * 17 + row * 11) % 64) / 64
                guard progress < threshold else { continue }
                path.addRect(CGRect(
                    x: rect.minX + CGFloat(column) * cellWidth,
                    y: rect.minY + CGFloat(row) * cellHeight - progress * CGFloat(4 + (column + row) % 7),
                    width: cellWidth + 0.5,
                    height: cellHeight + 0.5
                ))
            }
        }
        return path
    }
}
