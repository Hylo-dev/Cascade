//
//  EnvironmentValues+WidgetEditing.swift
//  CascadeKit
//

import SwiftUI

extension EnvironmentValues {

    /// isEditingWidgets is true while the widget board is being edited, set by each tile around
    /// its widget. A press on a widget then moves the widget, so the renderer's controls read it
    /// when they would act and send nothing: a long press that began on a button and ends with
    /// the board editing, the pointer still over the button, must not also press it. It changes
    /// nothing drawn, and only the controls read it.
    @Entry
    var isEditingWidgets = false
}
