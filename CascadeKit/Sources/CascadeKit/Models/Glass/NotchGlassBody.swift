//
//  NotchGlassBody.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CoreImage
import QuartzCore
import SwiftUI

/// NotchGlassBody is the rectangle the native glass covers: the notch body with
/// its convex bottom corners, extended one radius above the top edge so only
/// the bottom corners round. The concave shoulders and a detached bubble stay
/// outside it, under the near-opaque top of the tint gradient, where the old
/// full-outline glass was hidden anyway.
nonisolated struct NotchGlassBody: Equatable, Sendable {
    static let zero = NotchGlassBody(rect: .zero, cornerRadius: 0)

    let rect        : CGRect
    let cornerRadius: CGFloat

    init(rect: CGRect, cornerRadius: CGFloat) {
        self.rect         = rect
        self.cornerRadius = cornerRadius
    }

    init(geometry: NotchGeometry, centerX: CGFloat, topY: CGFloat) {
        let radius = max(0, min(geometry.bottomCornerRadius, geometry.height / 2, geometry.width / 2))
        self.init(
            rect: CGRect(
                x     : centerX - geometry.leftExtent,
                y     : topY - geometry.height,
                width : geometry.width,
                height: geometry.height + radius
            ),
            cornerRadius: radius
        )
    }

    /// transform maps a layer laid out at `reference` onto this body without a
    /// new layout. `anchor` is the layer's normalized anchor point: the layer
    /// renders local point p at origin + A + T(p − A), and T solves that to
    /// land on this body's origin + S·p for the per-axis scale S.
    func transform(
        from reference: NotchGlassBody,
        anchor        : CGPoint
    ) -> CGAffineTransform {
        let source = reference.rect
        guard source.width > 0, source.height > 0 else { return .identity }
        let scaleX = rect.width / source.width
        let scaleY = rect.height / source.height
        let anchorX = anchor.x * source.width
        let anchorY = anchor.y * source.height
        return CGAffineTransform(
            a : scaleX,
            b : 0,
            c : 0,
            d : scaleY,
            tx: rect.minX - source.minX + (scaleX - 1) * anchorX,
            ty: rect.minY - source.minY + (scaleY - 1) * anchorY
        )
    }
}
