//
//  PluginToggleStyle.swift
//  CascadeKit
//

import SwiftUI

/// PluginToggleStyle draws a plugin's toggle as its own label, a symbol or a text that flips on
/// a click, which is how the notch's controls look, instead of the macOS checkbox.
///
/// The whole frame of the label takes the click, as a plugin button's does. A plain button
/// hit-tests only what it draws, so a toggle laid transparently over a drawing, as Caffeinate's
/// power disc is, or one with gaps between its glyphs, would otherwise ignore the click.
struct PluginToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
