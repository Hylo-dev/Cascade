//
//  PluginVerticalAlignment+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginVerticalAlignment {

    var swiftUI: VerticalAlignment {
        switch self {
            case .top   : .top
            case .center: .center
            case .bottom: .bottom
        }
    }
}
