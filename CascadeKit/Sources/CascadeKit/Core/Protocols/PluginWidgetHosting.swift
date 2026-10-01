//
//  PluginWidgetHosting.swift
//  CascadeKit
//

/// PluginWidgetHosting is the part of the notch a plugin widget needs: placing it on the grid and
/// taking it off. The notch engine provides it; tests record it.
@MainActor
public protocol PluginWidgetHosting: AnyObject {

    func register(_ widget: NotchWidget)

    func unregisterWidget(id: WidgetIdentifier)
}
