//
//  PluginModifier.swift
//  CascadeKit
//

/// PluginModifier is one modifier, applied in the order the node lists them, as in SwiftUI.
/// `overlay` and `background` carry no content of their own: the n-th of them takes the node's
/// n-th layer. Keeping nodes out of the modifiers lets a node's own properties hash without
/// its layers, so a change inside a layer updates only the layer.
public enum PluginModifier: Codable, Hashable, Sendable {

    case font(PluginFont)
    case foregroundStyle(PluginForeground)
    case frame(width: Double?, height: Double?, maxWidth: PluginDimension?, maxHeight: PluginDimension?, alignment: PluginAlignment)
    case padding(PluginEdges, length: Double?)
    case opacity(Double)
    case clipShape(PluginShape)
    case lineLimit(Int)
    case minimumScaleFactor(Double)
    case contentTransition(PluginContentTransition)
    case transition(PluginTransition)
    case accessibilityLabel(String)
    case overlay(alignment: PluginAlignment)
    case background(alignment: PluginAlignment)

    /// isLayer tells the modifiers that take one of the node's layers.
    public var isLayer: Bool {
        switch self {
            case .overlay, .background:
                true

            default:
                false
        }
    }
}
