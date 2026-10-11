//
//  AudioAppsHostHealth.swift
//  CascadeKit
//

/// AudioAppsHostHealth is what the mixer needs to know about AudioHost's life, apart from the
/// snapshots it publishes: a snapshot can only come from a host that is alive, so the loss of one
/// has to arrive another way, or the columns would keep claiming a control that ended with the
/// process. The app's service reports it; the model reads it.
nonisolated public enum AudioAppsHostHealth: Equatable, Sendable {

    /// idle means nothing needs AudioHost, so it is not running and knows no apps.
    case idle

    /// running means AudioHost is connected; its snapshots speak for themselves.
    case running

    /// recovering means AudioHost was lost and is being brought back. Every app plays natively
    /// until it returns.
    case recovering

    /// givenUp means AudioHost kept failing. The apps play natively until the user restarts it.
    case givenUp
}
