//
//  SpotlightDropletLayout.swift
//  Cascade
//

import CoreGraphics
import Foundation

/// SpotlightDropletLayout resolves one compact overlay in global AppKit coordinates.
///
/// The source stays inside the hardware cutout. Its lower edge is four points
/// above the cutout's lower edge, so the glass container can form a neck without
/// exposing a second capsule beside the notch. Screen measurements are captured
/// once at presentation time; no screen or accessibility queries enter rendering.
nonisolated struct SpotlightDropletLayout: Equatable {
    let hardwareNotchBounds : CGRect
    let landingBounds       : CGRect
    let sourceBounds        : CGRect
    let canvasBounds        : CGRect

    /// init clamps unknown native dimensions before they can reach a view frame.
    init(
        screenFrame       : CGRect,
        hardwareNotchSize : CGSize,
        nativeSize        : CGSize
    ) {
        let notchWidth = min(
            Self.positiveDimension(hardwareNotchSize.width, fallback: 180),
            screenFrame.width
        )
        let notchHeight = min(
            Self.positiveDimension(hardwareNotchSize.height, fallback: 32),
            screenFrame.height
        )
        self.init(
            screenFrame       : screenFrame,
            restingNotchBounds: CGRect(
                x     : screenFrame.midX - notchWidth / 2,
                y     : screenFrame.maxY - notchHeight,
                width : notchWidth,
                height: notchHeight
            ),
            nativeSize        : nativeSize
        )
    }

    /// init uses the engine-owned resting bounds so hardware calibration and
    /// the fixed 96 × 8 software bump share the same visual handoff origin.
    init(
        screenFrame       : CGRect,
        restingNotchBounds: CGRect,
        nativeSize        : CGSize
    ) {
        let notchBounds = restingNotchBounds.standardized.intersection(screenFrame)
        let notchWidth  = max(1, notchBounds.width)
        let notchHeight = max(1, notchBounds.height)
        let targetWidth = min(
            Self.positiveDimension(nativeSize.width, fallback: 520),
            min(520, max(1, screenFrame.width - 48))
        )
        let targetHeight = min(
            Self.positiveDimension(nativeSize.height, fallback: 87),
            max(1, screenFrame.height - notchHeight - 32 - 24)
        )

        hardwareNotchBounds = notchBounds
        let landingX = min(
            max(screenFrame.minX + 24, notchBounds.midX - targetWidth / 2),
            screenFrame.maxX - 24 - targetWidth
        )
        landingBounds = CGRect(
            x      : landingX,
            y      : hardwareNotchBounds.minY - 32 - targetHeight,
            width  : targetWidth,
            height : targetHeight
        )
        let sourceWidth = min(88, max(1, notchWidth - 24))
        sourceBounds = CGRect(
            x      : notchBounds.midX - sourceWidth / 2,
            y      : hardwareNotchBounds.minY + min(4, notchHeight / 2),
            width  : sourceWidth,
            height : max(1, notchHeight - min(4, notchHeight / 2))
        )

        // Padding preserves the native glass rim and refraction outside its
        // nominal frame without paying for a full-screen compositing surface.
        let contentBounds = sourceBounds.union(landingBounds)
        canvasBounds = CGRect(
            x      : contentBounds.minX - 20,
            y      : contentBounds.minY - 20,
            width  : contentBounds.width + 40,
            height : screenFrame.maxY - contentBounds.minY + 20
        )
    }

    /// positiveDimension replaces unreadable AX sizes with the known native default.
    private static func positiveDimension(
        _ dimension : CGFloat,
        fallback    : CGFloat
    ) -> CGFloat {
        dimension.isFinite && dimension > 0 ? dimension : fallback
    }
}
