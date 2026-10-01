//
//  PluginFont+SwiftUI.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

extension PluginFont {

    /// swiftUI is the system font the plugin described: a fixed size when it gave one, its text
    /// style otherwise, so text follows the user's settings unless the plugin asked not to.
    var swiftUI: Font {
        let font: Font = if let size {
            .system(size: size, weight: weight?.swiftUI, design: design?.swiftUI)
        } else {
            .system(style?.swiftUI ?? .body, design: design?.swiftUI, weight: weight?.swiftUI)
        }

        return monospacedDigit ? font.monospacedDigit() : font
    }
}
