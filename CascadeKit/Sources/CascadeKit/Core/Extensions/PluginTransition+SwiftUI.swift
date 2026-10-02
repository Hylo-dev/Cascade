//
//  PluginTransition+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginTransition {

    var swiftUI: AnyTransition {
        switch self {
            case .opacity        : .opacity
            case .scale          : .scale
            case .move(let edges): .move(edge: edges.edge)
        }
    }
}
