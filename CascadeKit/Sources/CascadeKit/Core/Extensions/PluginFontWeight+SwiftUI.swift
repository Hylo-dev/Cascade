//
//  PluginFontWeight+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginFontWeight {

    var swiftUI: Font.Weight {
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
