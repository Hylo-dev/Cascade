//
//  SpotlightDropletFrame.swift
//  Cascade
//

import CoreGraphics
import Foundation

/// SpotlightDropletFrame contains allocation-free geometry for the two native glass surfaces.
nonisolated struct SpotlightDropletFrame: Equatable {
    let dropletBounds : CGRect
    let sourceBounds  : CGRect
    let opacity       : CGFloat
    let sourceOpacity : CGFloat
    let mergeSpacing  : CGFloat
    let cornerRadius  : CGFloat
    let isDetached    : Bool
    let isComplete    : Bool
}
