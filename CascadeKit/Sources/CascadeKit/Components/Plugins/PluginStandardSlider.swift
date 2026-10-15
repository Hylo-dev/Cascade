//
//  PluginStandardSlider.swift
//  CascadeKit
//

import SwiftUI

/// PluginStandardSlider is the kernel's plain `slider`: the system control over the node's
/// optimistic value. It exists so that the Reduce Motion setting is read by the control that
/// needs it, and not by every node of every document: a node's body that reads an environment
/// value is invalidated when it changes, and only a slider settles with an animation.
struct PluginStandardSlider: View {

    let value   : Binding<Double>
    let minimum : Double
    let maximum : Double
    let step    : Double?

    /// released lets go of the control with the animation its value settles in, nil under
    /// Reduce Motion: it sends the one action.
    let released: (Animation?) -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        if let step {
            Slider(value: value, in: minimum...maximum, step: step, onEditingChanged: editingChanged)
        } else {
            Slider(value: value, in: minimum...maximum, onEditingChanged: editingChanged)
        }
    }

    private func editingChanged(_ isEditing: Bool) {
        if !isEditing {
            released(reduceMotion ? nil : .snappy)
        }
    }
}
