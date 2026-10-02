//
//  PluginToggleStyle.swift
//  CascadeKit
//

import SwiftUI

/// PluginToggleStyle draws a plugin's toggle as its own label, a symbol or a text that flips on
/// a click, which is how the notch's controls look, instead of the macOS checkbox.
struct PluginToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(.plain)
    }
}
