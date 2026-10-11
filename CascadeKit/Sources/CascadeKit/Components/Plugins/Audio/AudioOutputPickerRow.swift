//
//  AudioOutputPickerRow.swift
//  CascadeKit
//

import Foundation

/// AudioOutputPickerRow is one line of the output selector, decided away from any view: which
/// output it is, the icon it wears and how it is marked. The picker draws a list of these and
/// nothing else, so what the user sees for a reading and a mode is testable as plain values.
///
/// A row never wears the mute or level icon of the current output: it is resolved as an unmuted
/// output at full level, so the row says what the device is, not how loud it happens to be.
///
/// An app's picker has one more row than the system's, first in the list: "Follow system", whose
/// `uid` is nil. It is checked when the app names no output, and it is never a checkbox, even in
/// several mode, because following the system excludes naming outputs.
struct AudioOutputPickerRow: Equatable, Identifiable {

    /// Marker is the trailing mark: a checkmark on the chosen output in single mode, a checkbox
    /// for every output in several mode.
    enum Marker: Equatable {

        case none
        case checkmark
        case checked
        case unchecked
    }

    /// followSystemIcon is what the "Follow system" row wears: a plain speaker, since it names no
    /// device.
    static let followSystemIcon = AudioOutputIcon.symbol("speaker.wave.2")

    private static let followSystemID = "follow-system"

    let uid   : String?
    let name  : String
    let icon  : AudioOutputIcon
    let marker: Marker

    var id: String { uid ?? Self.followSystemID }

    var isSelected: Bool {
        marker == .checkmark || marker == .checked
    }

    static func rows(
        for system          : SystemAudioState,
        allowsSeveralOutputs: Bool
    ) -> [AudioOutputPickerRow] {
        system.outputs.map { output in
            AudioOutputPickerRow(
                uid   : output.uid,
                name  : output.name,
                icon  : AudioOutputIcon.device(for: output),
                marker: marker(
                    isSelected          : system.selectedUIDs.contains(output.uid),
                    allowsSeveralOutputs: allowsSeveralOutputs
                )
            )
        }
    }

    /// rows(for:app:) lists an app's picker: "Follow system" first, then every output. What is
    /// checked comes from the outputs the app was asked to use (`intent.outputUIDs`), not from
    /// where it plays now, because a row is a choice the user made, and the system's output can
    /// move under an app that follows it.
    static func rows(
        for system          : SystemAudioState,
        app                 : AudioAppState,
        allowsSeveralOutputs: Bool
    ) -> [AudioOutputPickerRow] {
        let chosen = app.intent.outputUIDs
        let follow = AudioOutputPickerRow(
            uid   : nil,
            name  : String(localized: "Follow system", bundle: .module),
            icon  : followSystemIcon,
            marker: chosen.isEmpty ? .checkmark : .none
        )

        let outputs = system.outputs.map { output in
            AudioOutputPickerRow(
                uid   : output.uid,
                name  : output.name,
                icon  : AudioOutputIcon.device(for: output),
                marker: marker(
                    isSelected          : chosen.contains(output.uid),
                    allowsSeveralOutputs: allowsSeveralOutputs
                )
            )
        }

        return [follow] + outputs
    }

    /// marker is how an output's row is marked: a checkmark on the chosen one in single mode, a
    /// checkbox on every one in several mode.
    private static func marker(
        isSelected          : Bool,
        allowsSeveralOutputs: Bool
    ) -> Marker {
        if allowsSeveralOutputs {
            return isSelected ? .checked : .unchecked
        }

        return isSelected ? .checkmark : .none
    }
}
