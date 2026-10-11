//
//  AudioHostStatus.swift
//  Cascade
//

import CascadeKit

/// AudioHostStatus is how the per-app audio service reports AudioHost's health, for Settings.
nonisolated enum AudioHostStatus: Equatable, Sendable {

    /// idle means nothing needs AudioHost, so it is not running.
    case idle

    /// running means AudioHost is connected and answering.
    case running

    /// recovering means AudioHost was lost and is being brought back.
    case recovering

    /// givenUp means AudioHost kept failing; the apps play natively until the user restarts it.
    case givenUp

    /// health is what the mixer's model needs to know of it.
    var health: AudioAppsHostHealth {
        switch self {
            case .idle      : .idle
            case .running   : .running
            case .recovering: .recovering
            case .givenUp   : .givenUp
        }
    }
}
