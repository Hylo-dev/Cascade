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
}
