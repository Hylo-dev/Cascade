//
//  AudioMixerModel.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Observation

/// AudioMixerModel is what the volume widget and the output picker read and drive. The audio
/// service pushes `SystemAudioState` in through `receive`; the user's gestures go out through the
/// `SystemAudioControlling` seam, and the model shows their effect at once, before the system
/// confirms, so a drag never waits for a round trip.
///
/// A drag or a scroll burst can produce many levels per frame, and each controller call crosses
/// to the audio queue. So `adjust` keeps only the latest level and schedules a single main-queue
/// flush when none is pending: one hop per burst, no timer, nothing woken while idle. The level
/// is paired with the device it was made for, and the flush drops it if the default output moved
/// on meanwhile.
///
/// The system confirms a level late, Bluetooth outputs most of all, and the readings of the levels
/// sent during the drag can still be on their way when it ends. So after a drag or a scroll burst
/// the model keeps showing the level it sent until a reading confirms it, or until `settleWindow`
/// has passed, whichever comes first. It is a deadline checked when a reading arrives, not a
/// timer: nothing wakes while it waits.
///
/// The optimistic state is a guess: the next `receive` replaces an optimistic mute or selection
/// the system did not confirm, so a refused command heals itself without a rollback path.
///
/// The apps that play audio ride the same model. AudioHost's snapshots come in through
/// `receive(_:)` as `apps`, ordered by name; a gesture on one goes out through
/// `AudioAppsControlling` as a whole intent. A burst of gains from a drag shares the global
/// level's single main-queue hop: each app keeps only its latest, and the flush sends one intent
/// per app that moved. Mute and output choices are single gestures and go out at once.
///
/// When the system says it does not let Cascade capture audio (`captureAllowed == false`), an
/// app's tap would silence it without being able to play it back, so the apps are read-only: the
/// model refuses their commands and the columns show them at their native state. An unknown
/// answer (`nil`) is treated as allowed.
@MainActor
@Observable
public final class AudioMixerModel {

    /// capsuleHandoff lets the global capsule glide between the widget and the mixer. It lives
    /// here because the model is the one thing both already share; it is not observed.
    let capsuleHandoff = AudioCapsuleHandoff()

    public private(set) var system: SystemAudioState?

    public private(set) var isAdjusting = false

    /// allowsSeveralOutputs is the picker's toggle between choosing one output and building a
    /// multi-output.
    public var allowsSeveralOutputs = false

    /// apps are the apps producing audio, ordered by name, as AudioHost last reported them with
    /// the user's latest edits laid over.
    public private(set) var apps: [AudioAppState] = []

    /// captureAllowed is the system's answer on capturing audio: false when it was refused, nil
    /// while unknown.
    public private(set) var captureAllowed: Bool?

    /// adjustingApp is the app whose gain the user is dragging, if any.
    public private(set) var adjustingApp: AudioAppIdentity?

    /// areAppsReadOnly is true when capture was refused: the columns cannot be steered.
    public var areAppsReadOnly: Bool {
        captureAllowed == false
    }

    @ObservationIgnored
    private let controller: any SystemAudioControlling

    @ObservationIgnored
    private let appsController: (any AudioAppsControlling)?

    @ObservationIgnored
    private var pendingApps: Set<AudioAppIdentity> = []

    @ObservationIgnored
    private var pendingLevel: Double?

    @ObservationIgnored
    private var pendingDevice: UInt32 = 0

    @ObservationIgnored
    private var isFlushQueued = false

    /// settleWindow is how long, after a drag or a scroll burst, a reading that disagrees with the
    /// level sent is taken for a late echo of the drag and ignored.
    static let settleWindow = Duration.milliseconds(1500)

    /// settleTolerance is how close a reading must be to the level sent to confirm it: the system
    /// can round a level to its own steps.
    static let settleTolerance = 0.02

    /// settling is the level last sent and when its window closes, while a drag is settling.
    @ObservationIgnored
    private var settling: (level: Double, deviceID: UInt32, deadline: ContinuousClock.Instant)?

    @ObservationIgnored
    private var lastSentLevel: Double?

    @ObservationIgnored
    private let now: () -> ContinuousClock.Instant

    public convenience init(
        controller: any SystemAudioControlling,
        apps      : (any AudioAppsControlling)? = nil
    ) {
        self.init(
            controller: controller,
            apps      : apps,
            now       : { ContinuousClock.now }
        )
    }

    /// init(controller:apps:now:) takes the clock the settle window is read from, so a test can
    /// move time instead of waiting for it.
    init(
        controller: any SystemAudioControlling,
        apps      : (any AudioAppsControlling)?,
        now       : @escaping () -> ContinuousClock.Instant
    ) {
        self.controller     = controller
        self.appsController = apps
        self.now            = now
    }

    /// receive takes the service's latest reading. While the user is adjusting and the reading is
    /// for the same device, the optimistic level and mute stay, or the thumb would jump back under
    /// the finger and an unmuting drag would flash muted; a reading for another device is taken
    /// whole, since the drag's target changed. After the drag, while it settles, a reading that
    /// disagrees with the level sent is a late echo and keeps the optimistic level too; one that
    /// agrees, or any after the window, ends it.
    public func receive(_ state: SystemAudioState) {
        guard let current = system, current.defaultDeviceID == state.defaultDeviceID else {
            settling = nil
            system   = state
            return
        }
        if isAdjusting {
            system = state
                .replacing(level: current.level)
                .replacing(isMuted: current.isMuted)
            return
        }
        if let pending = settling {
            let isConfirmed = Swift.abs(state.level - pending.level) <= Self.settleTolerance
            let isExpired   = now() >= pending.deadline || pending.deviceID != state.defaultDeviceID

            if !isConfirmed, !isExpired {
                system = state.replacing(level: current.level)
                return
            }
            settling = nil
        }
        system = state
    }

    /// adjust moves the level at once on screen and queues it for the system. Moving the level
    /// of a muted output unmutes it, once, at the first move: the user is asking to hear it.
    /// While the drag lasts the capsule keeps that unmuted state even if a reading taken before
    /// the system obeyed still says muted.
    public func adjust(to level: Double) {
        guard var current = system else { return }

        if current.isMuted {
            current = current.replacing(isMuted: false)
            controller.setMuted(false, forDevice: current.defaultDeviceID)
        }

        let clamped = Swift.min(Swift.max(level, 0), 1)
        isAdjusting   = true
        system        = current.replacing(level: clamped)
        pendingLevel  = clamped
        pendingDevice = current.defaultDeviceID
        queueFlush()
    }

    /// endAdjusting sends what is still pending and leaves the adjusting state. Flushing here
    /// means the final level never waits for the queued hop.
    public func endAdjusting() {
        flush()
        isAdjusting = false

        if let level = lastSentLevel, let deviceID = system?.defaultDeviceID {
            settling = (level, deviceID, now() + Self.settleWindow)
        }
        lastSentLevel = nil
    }

    public func toggleMute() {
        guard let current = system else { return }

        let isMuted = !current.isMuted
        system = current.replacing(isMuted: isMuted)
        controller.setMuted(isMuted, forDevice: current.defaultDeviceID)
    }

    /// choose handles a tap on an output in the picker. In single mode that output becomes the
    /// system output. In several mode it joins or leaves the selection, except that the last one
    /// can never leave: a system with no output would be silent for no reason the user chose.
    public func choose(outputUID: String) {
        guard let current = system else { return }

        var uids = [outputUID]
        if allowsSeveralOutputs {
            uids = current.selectedUIDs
            if let index = uids.firstIndex(of: outputUID) {
                guard uids.count > 1 else { return }

                uids.remove(at: index)
            } else {
                uids.append(outputUID)
            }
        }
        system = current.replacing(selectedUIDs: uids)
        controller.selectOutputs(uids)
    }

    // MARK: - Apps

    /// receive takes AudioHost's latest state: the apps in name order and the capture answer.
    /// While the user drags an app's gain the optimistic gain stays, or the thumb would jump back
    /// under the finger; everything else is taken whole. Assigning only what changed keeps an
    /// identical repeat from redrawing the columns.
    public func receive(_ snapshot: AudioHostSnapshot) {
        var incoming = snapshot.apps.map(AudioAppState.init)

        if
            let adjustingApp,
            let held  = apps.first(where: { $0.identity == adjustingApp }),
            let index = incoming.firstIndex(where: { $0.identity == adjustingApp })
        {
            incoming[index] = incoming[index].replacing(gain: held.intent.gain)
        }
        incoming.sort(by: Self.isOrderedBefore)

        if apps != incoming {
            apps = incoming
        }
        if captureAllowed != snapshot.captureAllowed {
            captureAllowed = snapshot.captureAllowed
        }
    }

    /// receive(health:) takes the news that AudioHost itself changed. A lost host leaves no
    /// snapshot behind, so its apps are marked here: recovering while it is brought back, native
    /// once it is given up on, and forgotten when nothing runs it any more.
    public func receive(health: AudioAppsHostHealth) {
        switch health {
            case .running:
                break

            case .idle:
                if !apps.isEmpty {
                    apps = []
                }

            case .recovering:
                apps = apps.map { $0.replacing(enforcement: .recovering) }

            case .givenUp:
                apps = apps.map { $0.replacing(enforcement: .native) }
        }
    }

    /// setMixerVisible tells the service whether the mixer is on screen, because that decides
    /// whether AudioHost has to run while every intent is neutral.
    public func setMixerVisible(_ isVisible: Bool) {
        appsController?.setMixerVisible(isVisible)
    }

    /// adjust(app:to:) moves one app's gain at once on screen and queues the command, which the
    /// next flush sends with the latest value.
    public func adjust(
        app    : AudioAppIdentity,
        to gain: Double
    ) {
        guard !areAppsReadOnly, let index = apps.firstIndex(where: { $0.identity == app }) else { return }

        // Moving a muted app's gain unmutes it, as the system level does; the queued intent
        // carries both, so one command says "this loud, and audible".
        if apps[index].intent.isMuted {
            apps[index] = apps[index].replacing(isMuted: false)
        }
        adjustingApp = app
        apps[index]  = apps[index].replacing(gain: Swift.min(Swift.max(gain, 0), 1))
        pendingApps.insert(app)
        queueFlush()
    }

    /// endAdjusting(app:) sends what is still pending for the app and leaves the adjusting state.
    public func endAdjusting(app: AudioAppIdentity) {
        flushPending(app: app)
        if adjustingApp == app {
            adjustingApp = nil
        }
    }

    public func toggleMute(app: AudioAppIdentity) {
        guard !areAppsReadOnly, let index = apps.firstIndex(where: { $0.identity == app }) else { return }

        apps[index] = apps[index].replacing(isMuted: !apps[index].intent.isMuted)
        send(apps[index])
    }

    /// choose(outputUID:for:) handles a tap in an app's output picker. Nil is "Follow system":
    /// the intent names no output. In single mode an output is the app's only one. In several
    /// mode it joins or leaves the set, and a set emptied by the last leaving is the same as
    /// following the system, which is always a valid answer, so unlike the system's own picker
    /// nothing is refused. The set stops growing at the contract's limit.
    public func choose(
        outputUID: String?,
        for app  : AudioAppIdentity
    ) {
        guard !areAppsReadOnly, let index = apps.firstIndex(where: { $0.identity == app }) else { return }

        var uids: [String] = []
        if let outputUID {
            uids = [outputUID]
            if allowsSeveralOutputs {
                uids = apps[index].intent.outputUIDs
                if let position = uids.firstIndex(of: outputUID) {
                    uids.remove(at: position)
                } else {
                    guard uids.count < AudioAppIntent.maximumOutputs else { return }

                    uids.append(outputUID)
                }
            }
        }
        apps[index] = apps[index].replacing(outputUIDs: uids)
        send(apps[index])
    }

    /// returnToNative forgets what the user asked of the app and lets it play untouched again.
    public func returnToNative(app: AudioAppIdentity) {
        guard let index = apps.firstIndex(where: { $0.identity == app }) else { return }

        pendingApps.remove(app)
        apps[index] = apps[index].replacing(intent: .neutral)
        appsController?.returnToNative(app)
    }

    private func send(_ state: AudioAppState) {
        pendingApps.remove(state.identity)
        appsController?.setIntent(state.intent, for: state.identity)
    }

    private func flushPending(app: AudioAppIdentity) {
        guard
            pendingApps.remove(app) != nil,
            let state = apps.first(where: { $0.identity == app })
        else { return }

        appsController?.setIntent(state.intent, for: app)
    }

    /// isOrderedBefore sorts by the name the user reads, the way Finder does, and by bundle
    /// identifier when two apps share one so the order never flickers between snapshots.
    private static func isOrderedBefore(
        _ first : AudioAppState,
        _ second: AudioAppState
    ) -> Bool {
        switch first.displayName.localizedStandardCompare(second.displayName) {
            case .orderedAscending:
                true

            case .orderedDescending:
                false

            case .orderedSame:
                first.identity.bundleID < second.identity.bundleID
        }
    }

    // MARK: - Flushing

    private func queueFlush() {
        guard !isFlushQueued else { return }

        isFlushQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.flush()
            }
        }
    }

    /// flush sends the pending level and the pending apps. The level goes only to the device it
    /// was made for.
    private func flush() {
        isFlushQueued = false
        for app in pendingApps {
            flushPending(app: app)
        }
        guard let level = pendingLevel else { return }

        pendingLevel = nil
        guard pendingDevice == system?.defaultDeviceID else { return }

        controller.setLevel(level, forDevice: pendingDevice)
        lastSentLevel = level
    }
}
