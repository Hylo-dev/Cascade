//
//  BluetoothNoticeReducer.swift
//  CascadeKit
//

import CascadeContracts

/// BluetoothNoticeReducer decides what each Bluetooth state means for the notice. The source
/// numbers every transition and never reuses a number within one PluginHost, so a newer number
/// is a new event to show, and a higher revision of the event last shown only updates it, which
/// cannot renew its deadline. An older number is a late reading of an event already replaced on
/// screen and is ignored.
///
/// The first state is a baseline, whatever it says: a plugin that starts, or a PluginHost that
/// restarts, shows nothing for what is already connected. Event zero, the source's own baseline
/// when it starts again, forgets the last event the same way. A preview puts a sample on screen,
/// so until the next real event a late reading of the last one must not overwrite it.
struct BluetoothNoticeReducer: Sendable {

    private var lastEventID: UInt64?
    private var lastRevision = UInt64.zero
    private var canUpdate    = false

    mutating func receive(_ state: PluginBluetoothState) -> PluginNoticeDelivery? {
        guard let lastEventID, state.eventID != 0 else {
            remember(state, canUpdate: false)
            return nil
        }

        if state.eventID > lastEventID {
            remember(state, canUpdate: true)
            return .show
        }

        guard state.eventID == lastEventID, state.revision > lastRevision else { return nil }

        remember(state, canUpdate: canUpdate)
        return canUpdate ? .update : nil
    }

    /// previewShown records that the notice on screen is a sample now.
    mutating func previewShown() {
        canUpdate = false
    }

    private mutating func remember(
        _ state  : PluginBluetoothState,
        canUpdate: Bool
    ) {
        lastEventID    = state.eventID
        lastRevision   = state.revision
        self.canUpdate = canUpdate
    }
}
