//
//  PowerConnectionReducer.swift
//  Cascade
//

/// A transition to external power is the event. Capacity and Low Power Mode
/// changes only enrich it, so they cannot renew a notice's deadline.
nonisolated struct PowerConnectionReducer {
    private var previous: MacPowerSnapshot?
    private var revision: UInt64 = 0

    mutating func receive(_ snapshot: MacPowerSnapshot?) -> PowerConnectionUpdate? {
        guard let snapshot, snapshot != previous else { return nil }
        let old = previous
        previous = snapshot
        guard let old else { return nil }
        revision &+= 1
        if !snapshot.isExternalPower {
            return old.isExternalPower ? .disconnected : nil
        }
        return old.isExternalPower
            ? .updated(snapshot, revision: revision)
            : .connected(snapshot, revision: revision)
    }
}
