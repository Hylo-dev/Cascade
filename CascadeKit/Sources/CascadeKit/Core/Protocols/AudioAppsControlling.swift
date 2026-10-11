//
//  AudioAppsControlling.swift
//  CascadeKit
//

import CascadeContracts

/// AudioAppsControlling is how the mixer model tells the per-app audio service what the user
/// chose. The app's service implements it; the model depends on the contract, so tests drive it
/// with a recorder.
///
/// An intent is a request: the service stores it, so it outlives the app and the session, and
/// forwards it to AudioHost, which reports what it managed to enforce in a snapshot. The model
/// also says whether the mixer is on screen, because that decides whether AudioHost needs to run
/// at all while every intent is neutral.
@MainActor
public protocol AudioAppsControlling: AnyObject {

    func setIntent(
        _ intent: AudioAppIntent,
        for app : AudioAppIdentity
    )

    /// returnToNative forgets the intent for `app` and lets it play untouched again.
    func returnToNative(_ app: AudioAppIdentity)

    func setMixerVisible(_ isVisible: Bool)
}
