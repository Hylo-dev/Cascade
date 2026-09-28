//
//  MusicControlButtonStyle.swift
//  Cascade
//

import AppKit
import SwiftUI

/// A brief press response precedes the symbol's one-shot animation. Neither
/// feedback depends on the player reply or delays command dispatch.
struct MusicControlButtonStyle: ButtonStyle {

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
