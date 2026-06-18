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
/// touching the geometry math or the renderer. `fallbackRestingSize` is only
/// used on displays without a hardware notch — where a real cut-out exists we
/// measure it instead of guessing.
///
/// The corner radii come in two sets, `resting*` (closed) and `expanded*`
/// (open); the geometry interpolates between them as the notch morphs, so the
/// little closed pill and the big open island can carry entirely different
/// roundness.
@frozen
public nonisolated struct NotchConfiguration: Sendable {

    public let fallbackRestingSize: CGSize  // Used only when no hardware notch is present.
    public let expandedHalfWidth  : CGFloat // Each side's reach from center when fully open.
    public let expandedHeight     : CGFloat

    public let restingBottomCornerRadius : CGFloat // Convex bottom radius when closed.
    public let restingTopCornerRadius    : CGFloat // Concave (inverted) top radius when closed.
    public let expandedBottomCornerRadius: CGFloat // Convex bottom radius when fully open.
    public let expandedTopCornerRadius   : CGFloat // Concave (inverted) top radius when fully open.

    public let spring             : SpringParameters
    public let chromeColor        : Color   // The notch fill. Use Color(hex:) / Color(argb:) for convenience.

    /// Draw the chrome even on displays without a hardware notch. Production
    /// keeps this `false` (chrome only where the cut-out is, interaction
    /// everywhere); it exists so the notch can be *seen* while developing on a
    /// Mac or external display that has no physical notch.
    public let drawsChromeWithoutHardwareNotch: Bool

    public init(
        fallbackRestingSize             : CGSize,
        expandedHalfWidth               : CGFloat,
        expandedHeight                  : CGFloat,
        restingBottomCornerRadius       : CGFloat,
        restingTopCornerRadius          : CGFloat,
        expandedBottomCornerRadius      : CGFloat,
        expandedTopCornerRadius         : CGFloat,
        spring                          : SpringParameters,
        chromeColor                     : Color  = .black,
        drawsChromeWithoutHardwareNotch : Bool   = false
    ) {
        self.fallbackRestingSize             = fallbackRestingSize
        self.expandedHalfWidth               = expandedHalfWidth
        self.expandedHeight                  = expandedHeight
        self.restingBottomCornerRadius       = restingBottomCornerRadius
        self.restingTopCornerRadius          = restingTopCornerRadius
        self.expandedBottomCornerRadius      = expandedBottomCornerRadius
        self.expandedTopCornerRadius         = expandedTopCornerRadius
        self.spring                          = spring
        self.chromeColor                     = chromeColor
        self.drawsChromeWithoutHardwareNotch = drawsChromeWithoutHardwareNotch
    }

    /// The default look: a compact resting band that opens into a wide island,
    /// black, drawn only where a hardware notch exists.
    public static let `default` = NotchConfiguration(
        fallbackRestingSize       : CGSize(width: 220, height: 32),
        expandedHalfWidth         : 320.0,
        expandedHeight            : 180.0,
        restingBottomCornerRadius : 10.0,
        restingTopCornerRadius    : 4,
        expandedBottomCornerRadius: 22.0,
        expandedTopCornerRadius   : 12.0,
        spring                    : .snappy
    )

    /// A development look: bright fill, drawn on every display (even those with
    /// no hardware notch) so the overlay is unmistakable while wiring things up.
    public static let debug = NotchConfiguration(
        fallbackRestingSize             : CGSize(width: 220, height: 32),
        expandedHalfWidth               : 220.0,
        expandedHeight                  : 144.0,
        restingBottomCornerRadius       : 10.0,
        restingTopCornerRadius          : 4,
        expandedBottomCornerRadius      : 22.0,
        expandedTopCornerRadius         : 12.0,
        spring                          : .snappy,
        chromeColor                     : Color.red, // System-red.
        drawsChromeWithoutHardwareNotch : true
    )
}
