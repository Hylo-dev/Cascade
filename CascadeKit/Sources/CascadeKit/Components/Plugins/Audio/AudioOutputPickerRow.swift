//
//  AudioOutputPickerRow.swift
//  CascadeKit
//

/// AudioOutputPickerRow is one line of the output selector, decided away from any view: which
/// output it is, the icon it wears and how it is marked. The picker draws a list of these and
/// nothing else, so what the user sees for a reading and a mode is testable as plain values.
///
/// A row never wears the mute or level icon of the current output: it is resolved as an unmuted
/// output at full level, so the row says what the device is, not how loud it happens to be.
struct AudioOutputPickerRow: Equatable, Identifiable {

    /// Marker is the trailing mark: a checkmark on the chosen output in single mode, a checkbox
    /// for every output in several mode.
    enum Marker: Equatable {

        case none
        case checkmark
        case checked
        case unchecked
    }

    let uid   : String
    let name  : String
    let icon  : AudioOutputIcon
    let marker: Marker

    var id: String { uid }

    var isSelected: Bool {
        marker == .checkmark || marker == .checked
    }

    static func rows(
        for system          : SystemAudioState,
        allowsSeveralOutputs: Bool
    ) -> [AudioOutputPickerRow] {
        system.outputs.map { output in
            let isSelected = system.selectedUIDs.contains(output.uid)
            let marker: Marker
            if allowsSeveralOutputs {
                marker = isSelected ? .checked : .unchecked
            } else {
                marker = isSelected ? .checkmark : .none
            }

            return AudioOutputPickerRow(
                uid   : output.uid,
                name  : output.name,
                icon  : AudioOutputIcon.device(for: output),
                marker: marker
            )
        }
    }
}
