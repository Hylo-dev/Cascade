//
//  AudioVolumeCapsuleMetrics.swift
//  CascadeKit
//

import CoreGraphics

/// AudioVolumeCapsuleMetrics turns the width the capsule is given into every size it draws. The
/// grid widget keeps its 1x2 slots but draws a thinner pill, centred in them; the mixer lets the
/// capsule fill the width it offers. Both are one ratio, and the icon and the type follow the
/// capsule that is actually drawn, so a thin pill is not a fat pill's icon squeezed into it.
///
/// A ratio below one is a thinning, and a pill thinner than `minimumWidth` is too narrow to hold
/// an icon or to see, so it is floored there. A ratio of one or more means "fill the frame": the
/// frame is the caller's decision and is taken as given, however small. It is a pure function of
/// two numbers, so the proportions are tested without a view.
///
/// The icon's proportions are measured on the user's reference, in units of the capsule's width:
/// the symbol is 0.49 wide and its visual centre sits 0.51 above the capsule's bottom edge. The
/// symbol's font size is the same 0.49, so the glyph's width lands about on the box's.
struct AudioVolumeCapsuleMetrics: Equatable {

    static let minimumWidth: CGFloat = 12

    let width             : CGFloat
    let cornerRadius      : CGFloat
    let iconSize          : CGFloat
    let symbolFontSize    : CGFloat
    let iconCentre        : CGFloat
    let percentageFontSize: CGFloat

    /// iconInset is the gap between the icon box and the capsule's bottom edge that puts the box's
    /// centre at `iconCentre`.
    var iconInset: CGFloat {
        iconCentre - iconSize / 2
    }

    init(
        availableWidth: CGFloat,
        widthRatio    : CGFloat
    ) {
        let available = Swift.max(availableWidth, 0)
        let drawn     = widthRatio < 1
            ? Swift.max(available * widthRatio, Self.minimumWidth)
            : available

        width              = drawn
        cornerRadius       = drawn / 2
        iconSize           = drawn * 0.49
        symbolFontSize     = drawn * 0.49
        iconCentre         = drawn * 0.51
        percentageFontSize = Swift.max(drawn * 0.55, 9)
    }
}
