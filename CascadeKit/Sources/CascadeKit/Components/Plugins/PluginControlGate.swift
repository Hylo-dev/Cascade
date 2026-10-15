//
//  PluginControlGate.swift
//  CascadeKit
//

import SwiftUI

/// PluginControlGate hands a control whether the widget board is editing, so that the control
/// sends nothing while it is: a press on an editing board moves the widget, and the pointer is
/// still over the control when it lets go. It is the renderer's only reader of
/// `isEditingWidgets`, which keeps every other node free of that dependency, so editing starting
/// or ending draws the controls again and nothing else, each with actions that read the new
/// flag. A press that began before editing ends on the control drawn since, so the long press
/// that started editing sends nothing either.
struct PluginControlGate<Content: View>: View {

    @Environment(\.isEditingWidgets)
    private var isEditingWidgets

    /// content draws the control for whether the board is editing. It is internal so the tests
    /// can draw a control outside a window, as they draw every other node.
    let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isEditingWidgets)
    }
}
