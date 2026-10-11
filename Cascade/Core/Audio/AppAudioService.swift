//
//  AppAudioService.swift
//  Cascade
//

import CascadeContracts
import CascadeKit
import Dispatch

/// AppAudioService is the app side of the per-app volume: it keeps what the user asked of each
/// app, runs AudioHost while something needs it, and hands AudioHost's snapshots to the mixer's
/// model. The model reaches it through `AudioAppsControlling`.
///
/// The decisions are not made here. Everything that touches the connection, the intent store or
/// the clock lives in `AudioHostSession` on the serial queue the service is given, so the main
/// thread never waits on XPC or on the disk: this class only forwards a call with one queue hop
/// and delivers what comes back with one main-queue hop. Nothing runs between events; the
/// 3-second command deadline and the restart backoff are one-shot callbacks on that queue.
///
/// `onSnapshot` and `onStatus` are called on the main actor. The model wires the first to
/// `AudioMixerModel.receive(_:)`; Settings reads the second to show AudioHost's health and to
/// offer Restart when it was given up on.
@MainActor
final class AppAudioService: AudioAppsControlling {

    var onSnapshot: ((AudioHostSnapshot) -> Void)?
    var onStatus  : ((AudioHostStatus) -> Void)?

    private let connection: any AudioHostConnecting
    private let store     : AudioIntentStore
    private let queue     : DispatchQueue
    private let clock     : @Sendable () -> Duration
    private let schedule  : @Sendable (Duration, @escaping @Sendable () -> Void) -> Void

    /// session is lazy because it delivers back to the service, and a stored `let` cannot capture
    /// `self` before the service is fully built.
    private lazy var session = AudioHostSession(
        connection     : connection,
        store          : store,
        queue          : queue,
        clock          : clock,
        schedule       : schedule,
        deliverSnapshot: { [weak self] snapshot in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onSnapshot?(snapshot) }
            }
        },
        deliverStatus  : { [weak self] status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onStatus?(status) }
            }
        }
    )

    /// init reads the stored intents on the queue and starts AudioHost if one needs enforcing.
    /// `schedule` defaults to a one-shot `asyncAfter` on `queue`; tests pass a manual one.
    init(
        connection: any AudioHostConnecting,
        store     : AudioIntentStore,
        queue     : DispatchQueue,
        clock     : @escaping @Sendable () -> Duration,
        schedule  : (@Sendable (Duration, @escaping @Sendable () -> Void) -> Void)? = nil
    ) {
        self.connection = connection
        self.store      = store
        self.queue      = queue
        self.clock      = clock
        self.schedule   = schedule ?? { delay, work in
            let components = delay.components
            let seconds    = Double(components.seconds) + Double(components.attoseconds) / 1e18

            queue.asyncAfter(deadline: .now() + seconds, execute: work)
        }

        session.start()
    }

    func setIntent(
        _ intent: AudioAppIntent,
        for app : AudioAppIdentity
    ) {
        session.setIntent(intent, for: app)
    }

    func returnToNative(_ app: AudioAppIdentity) {
        session.returnToNative(app)
    }

    /// setMixerVisible starts AudioHost when the mixer is on screen or any stored intent is not
    /// neutral, and stops it when neither holds.
    func setMixerVisible(_ isVisible: Bool) {
        session.setMixerVisible(isVisible)
    }

    /// restart forgives AudioHost's faults and connects again.
    func restart() {
        session.restart()
    }
}
