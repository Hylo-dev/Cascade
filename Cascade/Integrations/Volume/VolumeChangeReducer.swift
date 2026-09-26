//
//  VolumeChangeReducer.swift
//  Cascade
//

/// SystemVolumeSnapshot carries copied CoreAudio values across isolation.
nonisolated struct SystemVolumeSnapshot: Equatable, Sendable {
    let deviceID: UInt32
    let scalar  : Double
    let isMuted : Bool
}

/// VolumeChangeEvent is the visible state of one real output-volume change.
nonisolated struct VolumeChangeEvent: Equatable, Sendable {
    let percentage: Int
    let isMuted   : Bool
    let revision  : UInt64
}

/// VolumeChangeReducer suppresses startup, duplicate and obsolete callbacks.
nonisolated struct VolumeChangeReducer {
    private var sessionID: UInt64 = 0
    private var previous : SystemVolumeSnapshot?
    private var revision : UInt64 = 0

    mutating func beginSession(_ sessionID: UInt64) {
        self.sessionID = sessionID
        previous = nil
    }

    mutating func receive(
        _ snapshot : SystemVolumeSnapshot,
        sessionID  : UInt64,
        allowsNotice: Bool,
        forcesFeedback: Bool = false
    ) -> VolumeChangeEvent? {
        guard self.sessionID == sessionID, snapshot.scalar.isFinite else { return nil }
        let oldSnapshot = previous
        previous = snapshot
        guard let oldSnapshot,
              oldSnapshot.deviceID == snapshot.deviceID,
              allowsNotice else { return nil }

        let percentage = Self.percentage(for: snapshot)
        guard forcesFeedback || percentage != Self.percentage(for: oldSnapshot)
                || snapshot.isMuted != oldSnapshot.isMuted else { return nil }
        revision &+= 1
        return VolumeChangeEvent(
            percentage: percentage,
            isMuted   : snapshot.isMuted,
            revision  : revision
        )
    }

    private static func percentage(for snapshot: SystemVolumeSnapshot) -> Int {
        snapshot.isMuted ? 0 : Int((min(1, max(0, snapshot.scalar)) * 100).rounded())
    }
}

/// VolumeKeyCommand identifies only the three volume media keys.
nonisolated enum VolumeKeyCommand: Hashable, Sendable {
    case increase
    case decrease
    case toggleMute
}

/// VolumeMediaKey decodes the public IOKit auxiliary key event representation.
nonisolated struct VolumeMediaKey: Equatable, Sendable {
    let command  : VolumeKeyCommand
    let isPressed: Bool
    let isRepeat : Bool

    init(command: VolumeKeyCommand, isPressed: Bool, isRepeat: Bool = false) {
        self.command = command
        self.isPressed = isPressed
        self.isRepeat = isRepeat
    }

    static func decode(
        subtype: Int16,
        data   : Int
    ) -> VolumeMediaKey? {
        guard subtype == 8 else { return nil }
        let command: VolumeKeyCommand
        switch (data >> 16) & 0xFFFF {
        case 0: command = .increase
        case 1: command = .decrease
        case 7: command = .toggleMute
        default: return nil
        }
        let state = (data >> 8) & 0xFF
        guard state == 0xA || state == 0xB else { return nil }
        return VolumeMediaKey(command: command, isPressed: state == 0xA, isRepeat: data & 0xFF != 0)
    }
}
