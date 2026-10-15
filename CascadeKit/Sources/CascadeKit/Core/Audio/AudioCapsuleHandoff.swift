//
//  AudioCapsuleHandoff.swift
//  CascadeKit
//

import CoreGraphics

/// AudioCapsuleHandoff carries the global volume capsule from the widget to the mixer and back.
/// The notch swaps the grid for the detail page by replacing its whole content, so the two
/// capsules never share a view tree and SwiftUI cannot match them. Instead each capsule writes
/// down where it is, in window coordinates, and when it leaves; the one that appears next, if
/// the other left a moment ago, starts where the other was and glides to its own place.
///
/// It is plain state on the main actor, not observed: nothing redraws when it changes, and a
/// capsule only reads it once, when it first knows its own frame. A capsule writes its frame only
/// when its layout changes, never per frame. A sighting is used once, so one swap glides once.
@MainActor
final class AudioCapsuleHandoff {

    /// Role is which of the two capsules is speaking.
    enum Role {

        case widget
        case mixer

        var other: Role {
            self == .widget ? .mixer : .widget
        }
    }

    /// Sighting is the last frame a capsule had and when it left, nil while it is on screen.
    private struct Sighting {

        var frame : CGRect
        var leftAt: ContinuousClock.Instant?
    }

    /// freshness is how long after a capsule leaves the other may still start from it: long
    /// enough to span the swap, short enough that reopening the notch later never glides.
    static let freshness: Duration = .milliseconds(500)

    private var widget: Sighting?
    private var mixer : Sighting?

    /// arrivedAt is when a capsule last started from the other one, so the page around it can
    /// tell, in the same swap, that it is arriving whichever of the two asks first.
    private var arrivedAt: (role: Role, instant: ContinuousClock.Instant)?

    private let now: () -> ContinuousClock.Instant

    init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// record notes the capsule's frame while it is on screen.
    func record(
        _ frame: CGRect,
        for role: Role
    ) {
        self[role] = Sighting(frame: frame, leftAt: nil)
    }

    /// leave notes that the capsule has gone, keeping its last frame for the other.
    func leave(_ role: Role) {
        self[role]?.leftAt = now()
    }

    /// origin is where the capsule of `role` should start from: the other capsule's last frame,
    /// if it is still on screen (the swap has not told it yet) or left within `freshness`. It
    /// consumes the sighting, so the answer is given once.
    func origin(for role: Role) -> CGRect? {
        guard let sighting = self[role.other], isFresh(sighting) else { return nil }

        self[role.other] = nil
        arrivedAt        = (role, now())
        return sighting.frame
    }

    /// isArriving says whether the capsule of `role` is gliding in from the other one in this
    /// swap: either the other's sighting is still waiting for it, or it has just taken it. It
    /// consumes nothing, so the page around the capsule can ask before or after the capsule does.
    func isArriving(_ role: Role) -> Bool {
        if let sighting = self[role.other], isFresh(sighting) {
            return true
        }
        guard let arrivedAt, arrivedAt.role == role else { return false }

        return now() - arrivedAt.instant <= Self.freshness
    }

    private func isFresh(_ sighting: Sighting) -> Bool {
        sighting.leftAt.map { now() - $0 <= Self.freshness } ?? true
    }

    private subscript(role: Role) -> Sighting? {
        get {
            role == .widget ? widget : mixer
        }
        set {
            if role == .widget {
                widget = newValue
            } else {
                mixer = newValue
            }
        }
    }
}
