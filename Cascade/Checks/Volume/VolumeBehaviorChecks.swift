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
        try checkMediaKeys()
        try checkMuteRepeat()
        try checkTapRecovery()
        try await checkPermissionObservation()
        try checkFailOpenRouting()
        try await checkBackgroundEventDecoding()

        print("Volume behavior tests: 42 passed")
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
