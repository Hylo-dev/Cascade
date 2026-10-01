//
//  PluginFontDesign+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginFontDesign {

    var swiftUI: Font.Design {
        switch self {
            case .standard  : .default
            case .rounded   : .rounded
            case .monospaced: .monospaced
            case .serif     : .serif
        }
    }
}
