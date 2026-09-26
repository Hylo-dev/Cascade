//
//  SoftwareNotchMetrics.swift
//  CascadeKit
//

import CoreGraphics

/// SoftwareNotchMetrics keeps the software silhouette, compact content, and
/// droplet connection as separate measurements. A low resting bump therefore
/// never shrinks activity content or reserves a camera cutout that is not there.
nonisolated struct SoftwareNotchMetrics: Equatable, Sendable {
    let restingSize     = CGSize(width: 96, height: 8)
    let compactHeight   : CGFloat = 32
    let compactCenterGap: CGFloat = 24
    let neckWidth       : CGFloat = 12
    let bodyOffset      : CGFloat = 8
}
