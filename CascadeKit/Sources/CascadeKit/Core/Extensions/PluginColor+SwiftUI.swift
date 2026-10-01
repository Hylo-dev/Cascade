//
//  PluginColor+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginColor {

    var swiftUI: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
