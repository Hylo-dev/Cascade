//
//  PluginAlignment+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginAlignment {

    var swiftUI: Alignment {
        switch self {
            case .center        : .center
            case .top           : .top
            case .bottom        : .bottom
            case .leading       : .leading
            case .trailing      : .trailing
            case .topLeading    : .topLeading
            case .topTrailing   : .topTrailing
            case .bottomLeading : .bottomLeading
            case .bottomTrailing: .bottomTrailing
        }
    }
}
