//
//  PluginHorizontalAlignment+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginHorizontalAlignment {

    var swiftUI: HorizontalAlignment {
        switch self {
            case .leading : .leading
            case .center  : .center
            case .trailing: .trailing
        }
    }
}
