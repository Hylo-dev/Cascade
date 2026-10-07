//
//  PluginFont+AppKit.swift
//  CascadeKit
//

import AppKit
import CascadeContracts

extension PluginFont {

    /// nsFont is the system font the plugin described, for the views that draw with AppKit: a
    /// fixed size when it gave one, the size of its text style otherwise, with its weight and
    /// design, and monospaced digits when it asked for them.
    var nsFont: NSFont {
        var font: NSFont

        if let size {
            font = .systemFont(ofSize: size, weight: weight?.nsWeight ?? .regular)
        } else {
            let preferred = NSFont.preferredFont(forTextStyle: style?.nsTextStyle ?? .body)

            font = weight.map { .systemFont(ofSize: preferred.pointSize, weight: $0.nsWeight) } ?? preferred
        }

        if let systemDesign = design?.nsDesign,
           let descriptor   = font.fontDescriptor.withDesign(systemDesign) {
            font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }

        return monospacedDigit ? font.monospacingDigits : font
    }
}

extension PluginFontWeight {

    var nsWeight: NSFont.Weight {
        switch self {
            case .ultraLight: .ultraLight
            case .thin      : .thin
            case .light     : .light
            case .regular   : .regular
            case .medium    : .medium
            case .semibold  : .semibold
            case .bold      : .bold
            case .heavy     : .heavy
            case .black     : .black
        }
    }
}

extension PluginFontDesign {

    var nsDesign: NSFontDescriptor.SystemDesign {
        switch self {
            case .standard  : .default
            case .rounded   : .rounded
            case .monospaced: .monospaced
            case .serif     : .serif
        }
    }
}

extension PluginTextStyle {

    var nsTextStyle: NSFont.TextStyle {
        switch self {
            case .largeTitle : .largeTitle
            case .title      : .title1
            case .title2     : .title2
            case .title3     : .title3
            case .headline   : .headline
            case .subheadline: .subheadline
            case .body       : .body
            case .callout    : .callout
            case .footnote   : .footnote
            case .caption    : .caption1
            case .caption2   : .caption2
        }
    }
}
