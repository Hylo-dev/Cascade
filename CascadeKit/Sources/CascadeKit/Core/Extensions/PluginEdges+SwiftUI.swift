//
//  PluginEdges+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginEdges {

    var swiftUI: Edge.Set {
        switch self {
            case .all       : .all
            case .horizontal: .horizontal
            case .vertical  : .vertical
            case .top       : .top
            case .bottom    : .bottom
            case .leading   : .leading
            case .trailing  : .trailing
        }
    }

    /// edge is the single edge a move transition slides along. Validation admits only single
    /// edges there, so the sets fall back to the bottom edge without ever being asked for.
    var edge: Edge {
        switch self {
            case .top                         : .top
            case .leading                     : .leading
            case .trailing                    : .trailing
            case .bottom, .all, .horizontal, .vertical: .bottom
        }
    }
}
