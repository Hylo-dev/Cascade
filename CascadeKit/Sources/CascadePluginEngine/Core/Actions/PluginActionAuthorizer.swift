//
//  PluginActionAuthorizer.swift
//  CascadeKit
//

import CascadeContracts

/// PluginActionAuthorizer turns a renderer's request into the event a plugin receives, with the
/// rules of `ActionAuthorizer`. The request must name the stored revision; the node must exist
/// in it and be a control whose value fits it, a button with none, a toggle with a bool, a
/// slider with a number in its range; and the feature must declare the control's action.
/// Anything else is refused, and the renderer reverts its optimistic value.
enum PluginActionAuthorizer {

    static func event(
        for request: PluginActionRequest,
        entry      : PluginPublicationStore.Entry?,
        feature    : PluginFeature
    ) -> PluginActionEvent? {
        guard let entry,
              entry.revision == request.revision,
              let index = entry.table.index(of: request.node)
        else { return nil }

        let action: String
        switch (entry.table.entries[index].kind, request.value) {
            case (.button(let name), nil):
                action = name

            case (.toggle(_, let name), .bool?):
                action = name

            case (.slider(_, let minimum, let maximum, _, let name), .number(let value)?) where value >= minimum && value <= maximum:
                action = name

            default:
                return nil
        }

        guard feature.actions.contains(action) else { return nil }

        return try? PluginActionEvent(feature: feature.id, action: action, value: request.value)
    }
}
