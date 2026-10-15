//
//  VolumeBehaviorChecks.swift
//  Cascade
//

#if VOLUME_MONITOR_TESTS
import Foundation
import AppKit

@main
enum VolumeBehaviorChecks {

    static func main() async throws {
        try checkVolumeChanges()
        try checkLevelUpdates()
        try checkMediaKeys()
        try checkLevelKeepsChannelBalance()
        try checkMuteRepeat()
        try checkTapRecovery()
        try await checkPermissionObservation()
        try await checkTapObservers()
        try checkFailOpenRouting()
        try await checkBackgroundEventDecoding()

        print("Volume behavior tests: 56 passed")
    }

    /// checkVolumeChanges exercises startup, native fallback, duplicates and
    /// callback generations without reading or changing any hardware volume.
    private static func checkVolumeChanges() throws {
        var reducer = VolumeChangeReducer()
        let initial = SystemVolumeSnapshot(
            deviceID: 1,
            scalar  : 0.5,
            isMuted : false
        )

        reducer.beginSession(1)
        try expect(
            reducer.receive(initial, sessionID: 1, allowsNotice: true) == nil,
            "Startup must be silent"
        )
        try expect(
            reducer.receive(initial, sessionID: 1, allowsNotice: true) == nil,
            "Duplicates must be silent"
        )

        let next = SystemVolumeSnapshot(
            deviceID: 1,
            scalar  : 0.75,
            isMuted : false
        )
        try expect(
            reducer.receive(next, sessionID: 1, allowsNotice: false) == nil,
            "Native fallback must not duplicate the HUD"
        )
        try expect(
            reducer.receive(next, sessionID: 1, allowsNotice: true) == nil,
            "Enabling replacement must not replay old changes"
        )

        let muted = SystemVolumeSnapshot(
            deviceID: 1,
            scalar  : 0.75,
            isMuted : true
        )
        let event = reducer.receive(
            muted,
            sessionID   : 1,
            allowsNotice: true
        )
        try expect(
            event?.isMuted == true && event?.percentage == 0,
            "Mute must display zero and a muted state"
        )

        let switched = SystemVolumeSnapshot(
            deviceID: 2,
            scalar  : 0.25,
            isMuted : false
        )
        try expect(
            reducer.receive(switched, sessionID: 1, allowsNotice: true) == nil,
            "Output switches establish a silent baseline"
        )

        reducer.beginSession(2)
        try expect(
            reducer.receive(initial, sessionID: 1, allowsNotice: true) == nil,
            "Stopped session callbacks must be ignored"
        )
        try expect(
            reducer.receive(initial, sessionID: 2, allowsNotice: true) == nil,
            "Restart must establish a silent baseline"
        )
        try expect(
            reducer.receive(initial, sessionID: 2, allowsNotice: true, forcesFeedback: true) != nil,
            "A handled key at a volume boundary still needs visible feedback"
        )
        try expect(
            reducer.receive(initial, sessionID: 2, allowsNotice: true) == nil,
            "Boundary feedback must not duplicate its observer callback"
        )
    }

    /// checkLevelKeepsChannelBalance covers the pure rule behind setScalar: an unbalanced pair
    /// keeps its distance when the level moves, and clamps at the ends. The checks cannot fake
    /// CoreAudio controls, so the rule is tested apart from the writes.
    private static func checkLevelKeepsChannelBalance() throws {
        let moved = CoreAudioSystemVolume.rebalanced([0.4, 0.6], to: 0.7)
        try expect(
            moved.count == 2 && abs(moved[0] - 0.6) < 0.0001 && abs(moved[1] - 0.8) < 0.0001,
            "An unbalanced pair must keep its balance: \(moved)"
        )

        let top = CoreAudioSystemVolume.rebalanced([0.4, 0.6], to: 1)
        try expect(abs(top[0] - 0.9) < 0.0001 && top[1] == 1, "Raising must clamp at 1: \(top)")

        let single = CoreAudioSystemVolume.rebalanced([0.3], to: 0.8)
        try expect(abs(single[0] - 0.8) < 0.0001, "One control must reach the target")
        try expect(CoreAudioSystemVolume.rebalanced([], to: 0.5).isEmpty, "No controls, no writes")
    }

    /// checkLevelUpdates holds the reducer to what each snapshot reports: an
    /// announcement for a change worth a notice, a level for any other change of
    /// what the volume shows, the first of a session included, and nothing for
    /// a level already reported. A level carries the last announcement's number,
    /// so whichever update a full stream keeps carries the newest number.
    private static func checkLevelUpdates() throws {
        var reducer = VolumeChangeReducer()
        let half    = SystemVolumeSnapshot(deviceID: 1, scalar: 0.5, isMuted: false)
        let louder  = SystemVolumeSnapshot(deviceID: 1, scalar: 0.75, isMuted: false)
        let quieter = SystemVolumeSnapshot(deviceID: 1, scalar: 0.25, isMuted: false)
        let other   = SystemVolumeSnapshot(deviceID: 2, scalar: 0.6, isMuted: false)

        reducer.beginSession(1)
        try expect(
            level(reducer.update(for: half, sessionID: 1, allowsNotice: true))
                == VolumeChangeEvent(percentage: 50, isMuted: false, revision: 0),
            "The first level of a session is a level, never a notice"
        )
        try expect(
            reducer.update(for: half, sessionID: 1, allowsNotice: true) == nil,
            "An equal level is not reported again"
        )
        try expect(
            announcement(reducer.update(for: louder, sessionID: 1, allowsNotice: true))
                == VolumeChangeEvent(percentage: 75, isMuted: false, revision: 1),
            "A key-driven change is announced"
        )
        try expect(
            reducer.update(for: louder, sessionID: 1, allowsNotice: true) == nil,
            "An announced level is not reported again as a level"
        )
        try expect(
            level(reducer.update(for: quieter, sessionID: 1, allowsNotice: false))
                == VolumeChangeEvent(percentage: 25, isMuted: false, revision: 1),
            "A change with no key is a level with the last announcement's number"
        )
        try expect(
            level(reducer.update(for: other, sessionID: 1, allowsNotice: true))
                == VolumeChangeEvent(percentage: 60, isMuted: false, revision: 1),
            "An output switch reports its level without a notice"
        )
        try expect(
            announcement(reducer.update(for: other, sessionID: 1, allowsNotice: true, forcesFeedback: true))
                == VolumeChangeEvent(percentage: 60, isMuted: false, revision: 2),
            "A handled key at a boundary is announced on an unchanged level"
        )
        try expect(
            reducer.update(for: quieter, sessionID: 7, allowsNotice: true) == nil,
            "A stopped session's callback reports nothing"
        )
    }

    private static func level(_ update: VolumeMonitorUpdate?) -> VolumeChangeEvent? {
        guard case .level(let event)? = update else { return nil }

        return event
    }

    private static func announcement(_ update: VolumeMonitorUpdate?) -> VolumeChangeEvent? {
        guard case .changed(let event)? = update else { return nil }

        return event
    }

    private static func checkMediaKeys() throws {
        try expect(
            VolumeMediaKey.decode(subtype: 8, data: 0x00000A00)?.command == .increase,
            "Volume up must decode"
        )
        try expect(
            VolumeMediaKey.decode(subtype: 8, data: 0x00010A01)?.isPressed == true,
            "Held key repeats must decode"
        )
        try expect(
            VolumeMediaKey.decode(subtype: 8, data: 0x00070B00)?.isPressed == false,
            "Mute key release must decode"
        )
        try expect(
            VolumeMediaKey.decode(subtype: 8, data: 0x00100A00) == nil,
            "Other media keys must pass through"
        )
    }

    private static func checkMuteRepeat() throws {
        let controller = FakeVolumeController()
        var router     = VolumeKeyRouter()
        guard let press = VolumeMediaKey.decode(subtype: 8, data: 0x00070A00),
              let repeated = VolumeMediaKey.decode(subtype: 8, data: 0x00070A01)
        else {
            throw VolumeCheckFailure.failed("Mute press and repeat must decode")
        }

        try expect(
            router.route(press, eligible: true, fineStep: false, controller: controller),
            "Mute press must be consumed"
        )
        try expect(
            router.route(repeated, eligible: true, fineStep: false, controller: controller),
            "Mute repeat of a handled gesture must be swallowed"
        )
        try expect(
            controller.commandCount == 1,
            "Holding mute must never toggle the device repeatedly"
        )

        var orphan = VolumeKeyRouter()
        try expect(
            !orphan.route(repeated, eligible: true, fineStep: false, controller: controller),
            "A mute repeat with no handled press belongs to the original handler"
        )
    }

    private static func checkTapRecovery() throws {
        var recovery = VolumeTapRecovery()
        try expect(
            recovery.shouldRetry(at: 10, hasPermission: true),
            "The first OS-disabled tap should recover"
        )
        try expect(
            !recovery.shouldRetry(at: 11, hasPermission: true),
            "Repeated failures must stop instead of fighting other input handlers"
        )
        try expect(
            recovery.shouldRetry(at: 16, hasPermission: true),
            "An isolated later failure may recover"
        )
        try expect(
            !recovery.shouldRetry(at: 22, hasPermission: false),
            "Revoked Accessibility must prevent recovery"
        )
        try expect(
            recovery.shouldRetry(at: 22, hasPermission: true),
            "Permission rejection must not consume the retry allowance"
        )
    }

    private static func checkPermissionObservation() async throws {
        let center  = NotificationCenter()
        let changes = VolumeAccessibilityObserver(
            permissions: center,
            workspace  : NotificationCenter(),
            settleDelay: .milliseconds(10)
        )
        let counter = PermissionRefreshCounter()

        changes.start { counter.count += 1 }
        try expect(counter.count == 0, "Permission observer must not poll at startup")

        for _ in 0..<5 {
            center.post(name: Notification.Name("com.apple.accessibility.api"), object: nil)
        }
        try await Task.sleep(for: .milliseconds(80))
        try expect(
            counter.count == 1,
            "Grant or revocation must refresh without a mounted status menu and coalesce its burst"
        )

        center.post(name: Notification.Name("com.apple.accessibility.api"), object: nil)
        changes.stop()
        try await Task.sleep(for: .milliseconds(80))
        try expect(counter.count == 1, "Stop must cancel an undelivered permission change")

        center.post(name: Notification.Name("com.apple.accessibility.api"), object: nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(counter.count == 1, "A stopped source must not refresh later")

        changes.start { counter.count += 1 }
        center.post(name: Notification.Name("com.apple.accessibility.api"), object: nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(counter.count == 2, "Restart must own exactly one fresh observation")

        changes.stop()
    }

    /// checkTapObservers holds the observers only the key tap needs to their
    /// switch: sleep, wake, activation and Accessibility changes reach the tap
    /// while they observe, and nothing wakes the app once they stop.
    private static func checkTapObservers() async throws {
        let workspace   = NotificationCenter()
        let application = NotificationCenter()
        let permissions = NotificationCenter()
        let observers   = VolumeTapObservers(
            workspace  : workspace,
            application: application,
            permissions: VolumeAccessibilityObserver(
                permissions: permissions,
                workspace  : workspace,
                settleDelay: .milliseconds(10)
            )
        )
        let counter = TapLifecycleCounter()

        try expect(!observers.isObserving, "Tap observers must not start on their own")

        observers.start(
            refresh: { counter.refreshes += 1 },
            suspend: { counter.suspends += 1 },
            resume : { counter.resumes += 1 }
        )
        try await postTapLifecycle(workspace: workspace, application: application, permissions: permissions)
        try expect(observers.isObserving, "Starting the tap observers must observe")
        try expect(
            counter.suspends == 1 && counter.resumes == 1 && counter.refreshes == 2,
            "Sleep, wake, activation and Accessibility changes must reach the tap"
        )

        observers.stop()
        try await postTapLifecycle(workspace: workspace, application: application, permissions: permissions)
        try expect(!observers.isObserving, "Stopping the tap observers must stop observing")
        try expect(
            counter.suspends == 1 && counter.resumes == 1 && counter.refreshes == 2,
            "Stopped tap observers must not wake the app"
        )
    }

    private static func postTapLifecycle(
        workspace  : NotificationCenter,
        application: NotificationCenter,
        permissions: NotificationCenter
    ) async throws {
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        permissions.post(name: Notification.Name("com.apple.accessibility.api"), object: nil)
        try await Task.sleep(for: .milliseconds(80))
    }

    private static func checkFailOpenRouting() throws {
        let controller = FakeVolumeController()
        var router     = VolumeKeyRouter()
        let down       = VolumeMediaKey(command: .increase, isPressed: true)
        let up         = VolumeMediaKey(command: .increase, isPressed: false)

        try expect(
            !router.route(up, eligible: true, fineStep: false, controller: controller),
            "Orphan key release must pass through"
        )

        controller.succeeds = false
        try expect(
            !router.route(down, eligible: true, fineStep: false, controller: controller),
            "Failed audio writes must pass through"
        )
        try expect(
            !router.allowsObservedNotice,
            "Native fallback must silence its subsequent CoreAudio callback"
        )

        controller.succeeds = true
        try expect(
            !router.route(down, eligible: true, fineStep: false, controller: controller),
            "A repeat after native fallback belongs to the native gesture"
        )
        try expect(
            !router.route(up, eligible: true, fineStep: false, controller: controller),
            "Native gesture release must pass through"
        )
        try expect(
            router.route(down, eligible: true, fineStep: false, controller: controller),
            "Only successful volume handling consumes the key"
        )
        try expect(
            router.route(up, eligible: true, fineStep: false, controller: controller),
            "Release matching consumed press must be consumed"
        )
        try expect(
            !router.route(down, eligible: false, fineStep: false, controller: controller),
            "Modified native shortcuts must pass through"
        )

        _ = router.route(
            up,
            eligible  : true,
            fineStep  : false,
            controller: controller
        )
        _ = router.route(
            down,
            eligible  : true,
            fineStep  : false,
            controller: controller
        )
        controller.succeeds = false
        try expect(
            !router.route(down, eligible: true, fineStep: false, controller: controller),
            "A failed repeat must return to native handling"
        )
        try expect(
            !router.route(up, eligible: true, fineStep: false, controller: controller),
            "Release after a failed repeat must reach native handling"
        )

        var boundedRouter = VolumeKeyRouter()
        _ = boundedRouter.route(
            down,
            eligible  : true,
            fineStep  : false,
            controller: controller,
            timestamp : 10
        )
        try expect(
            !boundedRouter.allowsObservedNotice(at: 10.1),
            "Immediate native observer callback must stay silent"
        )

        _ = boundedRouter.route(
            up,
            eligible  : true,
            fineStep  : false,
            controller: controller,
            timestamp : 10.5
        )
        try expect(
            !boundedRouter.allowsObservedNotice(at: 11),
            "Native release must cover delayed observer delivery"
        )
        try expect(
            boundedRouter.allowsObservedNotice(at: 12),
            "Later independent volume changes must become visible again"
        )
    }

    /// checkBackgroundEventDecoding catches the Swift 6 isolation crash that
    /// occurs if a C callback accidentally inherits the app's default actor.
    private static func checkBackgroundEventDecoding() async throws {
        let decoded = await Task.detached {
            let event = NSEvent.otherEvent(
                with         : .systemDefined,
                location     : .zero,
                modifierFlags: [],
                timestamp    : 0,
                windowNumber : 0,
                context      : nil,
                subtype      : 8,
                data1        : 0x00000A00,
                data2        : -1
            )
            guard let cgEvent = event?.cgEvent else { return false }

            return VolumeMediaKeyTap.decode(cgEvent)?.command == .increase
        }.value

        try expect(decoded, "A background Quartz callback must decode without entering MainActor")
    }
}

#endif
