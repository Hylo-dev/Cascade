//
//  FacePlacement.swift
//  CascadeKit
//

import CascadeContracts

/// FacePlacement is what fixes where a face's buttons sit on its tile: the face's own stack and
/// modifiers, the path to its row of buttons, the row's stack and number of slots, and the
/// modifiers of the time, whose fixed width sets where a row beside it starts. Two states whose
/// faces have equal placements put every slot in the same place, so a second press lands where
/// the first did.
struct FacePlacement: Equatable {

    let face     : PluginNodeKind
    let modifiers: [PluginModifier]
    let rowPath  : [Int]
    let row      : PluginNodeKind
    let slots    : Int
    let time     : [PluginModifier]

    init?(_ face: PluginNode) {
        guard let (path, row) = PluginNodeSearch.controlRow(in: face) else { return nil }

        let time = PluginNodeSearch.nodes(in: face).first { node in
            node.modifiers.contains { modifier in
                if case .minimumScaleFactor = modifier { return true }

                return false
            }
        }

        self.face      = face.kind
        self.modifiers = face.modifiers
        self.rowPath   = path
        self.row       = row.kind
        self.slots     = row.children.count
        self.time      = time?.modifiers ?? []
    }
}
