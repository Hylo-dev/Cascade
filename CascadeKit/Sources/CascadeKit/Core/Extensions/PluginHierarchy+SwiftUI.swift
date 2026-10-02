//
//  PluginHierarchy+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginHierarchy {

    var swiftUI: HierarchicalShapeStyle {
        switch self {
            case .primary   : .primary
            case .secondary : .secondary
            case .tertiary  : .tertiary
            case .quaternary: .quaternary
        }
    }
}
