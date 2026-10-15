//
//  PluginNodeModel.swift
//  CascadeKit
//

import CascadeContracts
import Observation

/// PluginNodeModel is one node of a rendered publication, observed on its own. The store
/// touches a model only when the kernel's diff names its node, and assigns only the properties
/// that changed, so SwiftUI invalidates only the views of nodes that changed. A control also
/// holds its optimistic value, the one the user just set, shown until the next publication or
/// until it reverts.
@Observable
final class PluginNodeModel {

    let id: PluginNodeID

    /// isControl is true for a button, a toggle or a slider. A node's identity carries the name
    /// of its kind, so a model never becomes another kind and this is decided once, and read
    /// without observing the kind's values.
    let isControl: Bool

    private(set) var kind     : PluginNodeKind
    private(set) var modifiers: [PluginModifier]
    private(set) var children : [PluginNodeID]
    private(set) var layers   : [PluginNodeID]

    var optimistic: PluginValue?
    var isDragging = false

    init(
        _ entry : PluginNodeTable.Entry,
        in table: PluginNodeTable
    ) {
        id        = entry.id
        isControl = switch entry.kind {
            case .button, .toggle, .slider: true
            default                       : false
        }
        kind      = entry.kind
        modifiers = entry.modifiers
        children  = entry.children.map { table.entries[$0].id }
        layers    = entry.layers.map { table.entries[$0].id }
    }

    func update(
        _ entry : PluginNodeTable.Entry,
        in table: PluginNodeTable
    ) {
        let children = entry.children.map { table.entries[$0].id }
        let layers   = entry.layers.map { table.entries[$0].id }

        if kind != entry.kind {
            kind = entry.kind
        }
        if modifiers != entry.modifiers {
            modifiers = entry.modifiers
        }
        if self.children != children {
            self.children = children
        }
        if self.layers != layers {
            self.layers = layers
        }
    }
}
