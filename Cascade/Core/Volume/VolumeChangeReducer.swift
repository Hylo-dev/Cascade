//
//  VolumeChangeReducer.swift
//  Cascade
//

/// VolumeChangeReducer suppresses startup, duplicate and obsolete callbacks.
nonisolated struct VolumeChangeReducer {

    private var sessionID: UInt64 = 0
    private var previous : SystemVolumeSnapshot?
    private var revision : UInt64 = 0

    mutating func beginSession(_ sessionID: UInt64) {
        self.sessionID = sessionID
        previous       = nil
    }

    mutating func receive(
        _ snapshot    : SystemVolumeSnapshot,
        sessionID     : UInt64,
        allowsNotice  : Bool,
        forcesFeedback: Bool = false
    ) -> VolumeChangeEvent? {
        guard self.sessionID == sessionID, snapshot.scalar.isFinite else { return nil }

        let oldSnapshot = previous
        previous = snapshot
        guard let oldSnapshot,
              oldSnapshot.deviceID == snapshot.deviceID,
              allowsNotice
        else { return nil }

        let percentage = Self.percentage(for: snapshot)
        guard forcesFeedback
              || percentage != Self.percentage(for: oldSnapshot)
              || snapshot.isMuted != oldSnapshot.isMuted
        else { return nil }

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
