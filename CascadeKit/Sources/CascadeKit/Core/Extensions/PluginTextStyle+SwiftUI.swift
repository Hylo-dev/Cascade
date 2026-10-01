//
//  PluginTextStyle+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginTextStyle {

    var swiftUI: Font.TextStyle {
        switch self {
            case .largeTitle : .largeTitle
            case .title      : .title
            case .title2     : .title2
            case .title3     : .title3
            case .headline   : .headline
            case .subheadline: .subheadline
            case .body       : .body
            case .callout    : .callout
            case .footnote   : .footnote
            case .caption    : .caption
            case .caption2   : .caption2
        }
    }
}
