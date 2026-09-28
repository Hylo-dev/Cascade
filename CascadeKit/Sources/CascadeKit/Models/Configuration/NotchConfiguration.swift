//
//  NotchConfiguration.swift
//  CascadeKit
//

import CoreGraphics
import SwiftUI

/// NotchConfiguration is the static design of the notch: how big it rests, how
/// far it expands, how round it is (closed *and* open), and how its morph
/// spring behaves.
///
/// It is injected into the engine so the look can be tuned (or themed) without
/// touching the geometry math or the renderer. `fallbackRestingSize` remains a
/// source-compatible configuration value; the current software-notch styles
/// use `SoftwareNotchMetrics` so old saved calibration and theme values cannot
/// enlarge the fixed 96 × 8 bump.
///
/// The corner radii come in two sets, `resting*` (closed) and `expanded*`
/// (open); the geometry interpolates between them as the notch morphs, so the
/// little closed pill and the big open island can carry entirely different
/// roundness.
@frozen
public nonisolated struct NotchConfiguration: Sendable {

    public let fallbackRestingSize: CGSize  // Legacy fallback retained for source compatibility.
    public let compactActivityExtension: CGFloat // Extra reach per side while an activity is compact.
    public let expandedHalfWidth  : CGFloat // Each side's reach from center when fully open.
    public let expandedHeight     : CGFloat // Height of the ordinary widget surface.
    public let maximumActivityExpandedHeight: CGFloat // Activities size to content, up to this height.

    public let restingBottomCornerRadius : CGFloat // Convex bottom radius when closed.
    public let restingTopCornerRadius    : CGFloat // Concave (inverted) top radius when closed.
    public let expandedBottomCornerRadius: CGFloat // Convex bottom radius when fully open.
    public let expandedTopCornerRadius   : CGFloat // Concave (inverted) top radius when fully open.

    public let spring             : SpringParameters
    public let chromeColor        : Color   // The notch fill. Use Color(hex:) / Color(argb:) for convenience.

    /// Draw the compact fallback chrome on displays without a hardware notch.
    /// The default keeps this enabled so external displays retain the same
    /// interaction surface; custom configurations may opt out.
    public let drawsChromeWithoutHardwareNotch: Bool

    public init(
        fallbackRestingSize             : CGSize,
        compactActivityExtension        : CGFloat = 64,
        expandedHalfWidth               : CGFloat,
        expandedHeight                  : CGFloat,
        restingBottomCornerRadius       : CGFloat,
        restingTopCornerRadius          : CGFloat,
        expandedBottomCornerRadius      : CGFloat,
        expandedTopCornerRadius         : CGFloat,
        spring                          : SpringParameters,
        chromeColor                     : Color  = .black,
        drawsChromeWithoutHardwareNotch : Bool   = false,
        maximumActivityExpandedHeight  : CGFloat? = nil
    ) {
        self.fallbackRestingSize             = fallbackRestingSize
        self.compactActivityExtension        = compactActivityExtension
        self.expandedHalfWidth               = expandedHalfWidth
        self.expandedHeight                  = expandedHeight
        self.maximumActivityExpandedHeight   = maximumActivityExpandedHeight ?? expandedHeight
        self.restingBottomCornerRadius       = restingBottomCornerRadius
        self.restingTopCornerRadius          = restingTopCornerRadius
        self.expandedBottomCornerRadius      = expandedBottomCornerRadius
        self.expandedTopCornerRadius         = expandedTopCornerRadius
        self.spring                          = spring
        self.chromeColor                     = chromeColor
        self.drawsChromeWithoutHardwareNotch = drawsChromeWithoutHardwareNotch
    }

    /// The default look: a compact black band that remains visible on external
    /// displays and opens into a wide island.
    public static let `default` = NotchConfiguration(
        fallbackRestingSize             : SoftwareNotchMetrics().restingSize,
        compactActivityExtension        : 64,
        expandedHalfWidth               : 220.0,
        expandedHeight                  : 144.0,
        restingBottomCornerRadius       : 14.0,
        restingTopCornerRadius          : 4,
        expandedBottomCornerRadius      : 44.0,
        expandedTopCornerRadius         : 18.0,
        spring                          : .snappy,
        drawsChromeWithoutHardwareNotch : true,
        maximumActivityExpandedHeight  : 240
    )

    /// A development look: bright fill, drawn on every display (even those with
    /// no hardware notch) so the overlay is unmistakable while wiring things up.
    public static let debug = NotchConfiguration(
        fallbackRestingSize             : SoftwareNotchMetrics().restingSize,
        compactActivityExtension        : 64,
        expandedHalfWidth               : 220.0,
        expandedHeight                  : 144.0,
        restingBottomCornerRadius       : 14.0,
        restingTopCornerRadius          : 4,
        expandedBottomCornerRadius      : 44.0,
        expandedTopCornerRadius         : 18.0,
        spring                          : .snappy,
        chromeColor                     : Color.red, // System-red.
        drawsChromeWithoutHardwareNotch : true
    )
}
