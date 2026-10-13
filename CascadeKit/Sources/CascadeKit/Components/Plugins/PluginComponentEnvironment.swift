//
//  PluginComponentEnvironment.swift
//  CascadeKit
//

import SwiftUI

extension EnvironmentValues {

    /// pluginComponentServices is what the components of a widget or a detail read their models
    /// from; nil outside the kernel's surfaces, such as a preview.
    @Entry var pluginComponentServices: PluginComponentServices? = nil

    /// pluginOpenDetail opens the detail page of the widget that draws this content, and is nil
    /// when its feature declares none, so a component never offers a tap that goes nowhere.
    @Entry var pluginOpenDetail: (@MainActor () -> Void)? = nil

    /// pluginPageObstruction is the part of a detail page the hardware notch covers, in the page's
    /// own coordinates (the top centre), so a component can lay itself out around it. It is zero
    /// where there is no obstruction: on a widget, or on a display without a notch.
    @Entry var pluginPageObstruction: CGRect = .zero
}
