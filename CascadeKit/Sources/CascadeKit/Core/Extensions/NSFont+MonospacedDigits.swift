//
//  NSFont+MonospacedDigits.swift
//  CascadeKit
//

import AppKit
import CoreText

extension NSFont {

    /// monospacingDigits is this font with its digits all one width, whatever the font is. The
    /// system font draws proportional digits by default, and a label that rolls one digit at a
    /// time must not shift its neighbours when a one becomes a zero.
    var monospacingDigits: NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier    : kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])

        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
