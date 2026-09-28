//
//  DisplaySettingsModel.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// DisplaySettingsModel builds stable picker rows without treating a display
/// name as identity. The selected offline UUID remains available for reconnect.
nonisolated enum DisplaySettingsModel {

    struct ActivityDisplayChoice: Identifiable, Equatable {

        let identity          : DisplayIdentity
        let name              : String
        let isConnected       : Bool
        let accessibilityLabel: String

        var id: DisplayIdentity { identity }
    }

    static func activityDisplayChoices(
        displays: [NotchDisplayDescriptor],
        selected: DisplayIdentity?
    ) -> [ActivityDisplayChoice] {
        var choices = displays.compactMap { display -> ActivityDisplayChoice? in
            guard let identity = display.identity else { return nil }

            return ActivityDisplayChoice(
                identity          : identity,
                name              : display.name,
                isConnected       : true,
                accessibilityLabel: "\(display.name), \(identity.rawValue)"
            )
        }

        if let selected, !choices.contains(where: { $0.identity == selected }) {
            choices.append(ActivityDisplayChoice(
                identity          : selected,
                name              : String(localized: "Disconnected Display"),
                isConnected       : false,
                accessibilityLabel: String(localized: "Disconnected Display, \(selected.rawValue)")
            ))
        }

        return choices
    }
}
