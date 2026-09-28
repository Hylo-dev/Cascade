//
//  ActivityDisplayRouting.swift
//  CascadeKit
//

/// ActivityDisplayRouting resolves the compact Live Activity destinations from
/// already-normalized identities.
///
/// This function stays free of AppKit and preferences so the coordinator can
/// apply a topology snapshot atomically. Focus fallback is resolved before this
/// boundary; a missing focused or fixed display intentionally yields no copy.
nonisolated enum ActivityDisplayRouting {

    static func destinations(
        mode     : LiveActivityDisplayMode,
        connected: Set<DisplayIdentity>,
        focused  : DisplayIdentity?
    ) -> Set<DisplayIdentity> {
        switch mode {
            case .allDisplays:
                connected
            case .focusedDisplay:
                focused.flatMap { connected.contains($0) ? [$0] : [] } ?? []
            case let .fixedDisplay(identity):
                connected.contains(identity) ? [identity] : []
        }
    }
}
