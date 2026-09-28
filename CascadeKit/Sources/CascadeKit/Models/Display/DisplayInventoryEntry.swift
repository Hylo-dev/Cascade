//
//  DisplayInventoryEntry.swift
//  CascadeKit
//

/// DisplayInventoryEntry joins one session snapshot to its optional persistent
/// identity and user-facing system name.
///
/// `identity` is nil when CoreGraphics cannot provide a UUID. The coordinator
/// may still address that screen by `snapshot.displayID` for the current
/// session, but it must not invent a value suitable for persistence.
nonisolated struct DisplayInventoryEntry: Equatable, Sendable {

    let snapshot: ActiveDisplay
    let identity: DisplayIdentity?
    let name    : String

    init(
        snapshot: ActiveDisplay,
        identity: DisplayIdentity?,
        name    : String
    ) {
        self.snapshot = snapshot
        self.identity = identity
        self.name     = name
    }
}
