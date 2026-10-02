//
//  VolumeChangeReducer.swift
//  Cascade
//

/// VolumeChangeReducer suppresses startup, duplicate and obsolete callbacks.
/// `receive` decides which changes deserve a notice; `update` adds what shows
/// the level without announcing it: every other change of the visible level,
/// the first of a session included, once, with the last announcement's number.
nonisolated struct VolumeChangeReducer {

    private var sessionID: UInt64 = 0
    private var previous : SystemVolumeSnapshot?
    private var revision : UInt64 = 0
    private var reported : (percentage: Int, isMuted: Bool)?

    mutating func beginSession(_ sessionID: UInt64) {
        self.sessionID = sessionID
        previous       = nil
        reported       = nil
    }

    /// update is what a snapshot reports: an announcement, a level that was not
    /// announced, or nothing for a level already reported or an obsolete callback.
    mutating func update(
        for snapshot  : SystemVolumeSnapshot,
        sessionID     : UInt64,
        allowsNotice  : Bool,
        forcesFeedback: Bool = false
    ) -> VolumeMonitorUpdate? {
        guard self.sessionID == sessionID, snapshot.scalar.isFinite else { return nil }

        let level = (percentage: Self.percentage(for: snapshot), isMuted: snapshot.isMuted)
        defer { reported = level }

        if let event = receive(
            snapshot,
            sessionID     : sessionID,
            allowsNotice  : allowsNotice,
            forcesFeedback: forcesFeedback
        ) {
            return .changed(event)
        }
        guard reported.map({ $0 != level }) ?? true else { return nil }

        return .level(VolumeChangeEvent(percentage: level.percentage, isMuted: level.isMuted, revision: revision))
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
