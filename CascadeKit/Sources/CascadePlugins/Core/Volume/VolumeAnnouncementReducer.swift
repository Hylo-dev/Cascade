//
//  VolumeAnnouncementReducer.swift
//  CascadeKit
//

import CascadeContracts

/// VolumeAnnouncementReducer turns the volume source's states into notices. The first state is a
/// baseline, so a plugin that starts, or a PluginHost that restarts and replays the latest state,
/// shows nothing; afterwards a notice is due whenever the announcement counter moves to a value it
/// has not seen. A new session starts at counter zero, which shows nothing and makes its first
/// announcement new again.
struct VolumeAnnouncementReducer: Sendable {

    private var last: UInt64?

    mutating func receive(_ state: PluginVolumeState) -> Bool {
        defer { last = state.announcement }

        guard let last else { return false }

        return state.announcement != 0 && state.announcement != last
    }
}
