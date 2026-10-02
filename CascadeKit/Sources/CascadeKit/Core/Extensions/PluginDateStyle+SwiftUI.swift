//
//  PluginDateStyle+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginDateStyle {

    var swiftUI: Text.DateStyle {
        switch self {
            case .time    : .time
            case .date    : .date
            case .relative: .relative
        }
    }
}
