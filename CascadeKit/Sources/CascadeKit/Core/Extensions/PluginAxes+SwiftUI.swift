//
//  PluginAxes+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginAxes {

    var swiftUI: Axis.Set {
        switch self {
            case .horizontal: .horizontal
            case .vertical  : .vertical
            case .both      : [.horizontal, .vertical]
        }
    }
}
