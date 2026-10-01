//
//  PluginDimension+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics

extension PluginDimension {

    var swiftUI: CGFloat {
        switch self {
            case .points(let value): CGFloat(value)
            case .infinity         : .infinity
        }
    }
}
