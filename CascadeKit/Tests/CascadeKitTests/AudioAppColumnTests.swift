//
//  AudioAppColumnTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CoreAudio
import Synchronization
import Testing
@testable import CascadeKit

/// AudioAppColumnTests check what an app column and its output selector decide, away from any
/// view: which rows the app's picker lists and how they are marked, what a column shows while the
/// system refuses audio capture, when it offers the way back to native audio, and how the icons
/// load. The views are hosted once, in `AudioMixerComponentTests`, to prove they render.
@MainActor
struct AudioAppColumnTests {

    private func system(selected: [String] = ["a"]) -> SystemAudioState {
        SystemAudioState(
            level          : 0.5,
            isMuted        : false,
            supportsVolume : true,
            outputs        : [
                AudioOutputDevice(uid: "a", name: "MacBook Speakers", transportType: kAudioDeviceTransportTypeBuiltIn, bluetooth: nil),
                AudioOutputDevice(uid: "b", name: "Studio Display", transportType: kAudioDeviceTransportTypeDisplayPort, bluetooth: nil),
            ],
            selectedUIDs   : selected,
            defaultDeviceID: 7
        )
    }

    private func app(
        gain       : Double = 1,
        isMuted    : Bool = false,
        outputUIDs : [String] = [],
        enforcement: AudioAppEnforcement = .applied,
        effective  : [String] = []
    ) throws -> AudioAppState {
        AudioAppState(
            try AudioAppFixture.app(
                "com.apple.Music",
                name               : "Music",
                intent             : try AudioAppFixture.intent(gain: gain, isMuted: isMuted, outputUIDs: outputUIDs),
                enforcement        : enforcement,
                effectiveOutputUIDs: effective
            )
        )
    }

    @Test
    func followSystemIsTheFirstPickerRowAndClearsOutputs() throws {
        let music = try app()
        let rows  = AudioOutputPickerRow.rows(
            for                 : system(),
            app                 : music,
            allowsSeveralOutputs: false
        )

        #expect(rows.map(\.uid) == [nil, "a", "b"])
        #expect(rows.first?.name == "Follow system")
        #expect(rows.first?.marker == .checkmark)
        #expect(rows.dropFirst().map(\.marker) == [.none, .none])
        #expect(Set(rows.map(\.id)).count == rows.count)

        let controller = RecordingAudioAppsController()
        let model      = AudioMixerModel(controller: RecordingSystemAudioController(), apps: controller)
        model.receive(
            try AudioAppFixture.snapshot(
                [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(outputUIDs: ["b"]), enforcement: .applied)]
            )
        )
        var closed = 0

        AudioOutputPicker.choose(
            nil,
            for    : music.identity,
            in     : model,
            onClose: { closed += 1 }
        )

        #expect(controller.intents.map(\.outputUIDs) == [[]])
        #expect(closed == 1)
    }

    @Test
    func theAppsPickerMarksWhatTheAppWasAskedToUse() throws {
        let single = AudioOutputPickerRow.rows(
            for                 : system(),
            app                 : try app(outputUIDs: ["b"]),
            allowsSeveralOutputs: false
        )
        let several = AudioOutputPickerRow.rows(
            for                 : system(),
            app                 : try app(outputUIDs: ["a", "b"]),
            allowsSeveralOutputs: true
        )
        let severalFollowing = AudioOutputPickerRow.rows(
            for                 : system(),
            app                 : try app(),
            allowsSeveralOutputs: true
        )

        #expect(single.map(\.marker) == [.none, .none, .checkmark])
        #expect(several.map(\.marker) == [.none, .checked, .checked])
        #expect(severalFollowing.map(\.marker) == [.checkmark, .unchecked, .unchecked])
    }

    @Test
    func theAppsPickerStaysOpenInSeveralMode() throws {
        let controller = RecordingAudioAppsController()
        let model      = AudioMixerModel(controller: RecordingSystemAudioController(), apps: controller)
        model.receive(try AudioAppFixture.snapshot([try AudioAppFixture.app("com.apple.Music", name: "Music")]))
        model.allowsSeveralOutputs = true
        var closed = 0

        AudioOutputPicker.choose(
            "a",
            for    : try AudioAppFixture.identity("com.apple.Music"),
            in     : model,
            onClose: { closed += 1 }
        )

        #expect(controller.intents.map(\.outputUIDs) == [["a"]])
        #expect(closed == 0)
    }

    @Test
    func captureDeniedMakesColumnsReadOnly() throws {
        let asked = try app(gain: 0.2, isMuted: true, outputUIDs: ["b"], enforcement: .notApplied)

        #expect(AudioAppColumn.level(of: asked, isReadOnly: true) == 1)
        #expect(!AudioAppColumn.isMuted(asked, isReadOnly: true))
        #expect(!AudioAppColumn.isDashed(asked, isReadOnly: true))
        #expect(!AudioAppColumn.offersReturnToNative(asked, isReadOnly: true))
        #expect(AudioAppColumn.accessibilityValue(of: asked, isReadOnly: true) == "100%")

        #expect(AudioAppColumn.level(of: asked, isReadOnly: false) == 0.2)
        #expect(AudioAppColumn.isMuted(asked, isReadOnly: false))

        let controller = RecordingAudioAppsController()
        let model      = AudioMixerModel(controller: RecordingSystemAudioController(), apps: controller)
        model.receive(
            try AudioAppFixture.snapshot(
                [try AudioAppFixture.app("com.apple.Music", name: "Music")],
                captureAllowed: false
            )
        )

        #expect(model.areAppsReadOnly)
        #expect(AudioMixerComponent.captureSettingsAddress == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    @Test
    func notAppliedShowsTheReturnToNativeAction() throws {
        let notApplied = try app(gain: 0.3, enforcement: .notApplied)
        let native     = try app(isMuted: true, enforcement: .native)
        let applied    = try app(gain: 0.3, enforcement: .applied)
        let recovering = try app(gain: 0.3, enforcement: .recovering)
        let untouched  = try app(enforcement: .native)
        let neutral    = try app(enforcement: .notApplied)

        #expect(AudioAppColumn.offersReturnToNative(notApplied, isReadOnly: false))
        #expect(AudioAppColumn.isDashed(notApplied, isReadOnly: false))
        #expect(AudioAppColumn.offersReturnToNative(native, isReadOnly: false))
        #expect(!AudioAppColumn.offersReturnToNative(applied, isReadOnly: false))
        #expect(!AudioAppColumn.offersReturnToNative(recovering, isReadOnly: false))
        #expect(!AudioAppColumn.offersReturnToNative(untouched, isReadOnly: false))
        #expect(!AudioAppColumn.offersReturnToNative(neutral, isReadOnly: false))
        #expect(AudioAppColumn.accessibilityValue(of: notApplied, isReadOnly: false) == "30%, Not applied")

        let controller = RecordingAudioAppsController()
        let model      = AudioMixerModel(controller: RecordingSystemAudioController(), apps: controller)
        model.receive(
            try AudioAppFixture.snapshot(
                [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.3), enforcement: .notApplied)]
            )
        )
        model.returnToNative(app: notApplied.identity)

        #expect(controller.returned == [notApplied.identity])
    }

    @Test
    func recoveringIsShownOnTheIconAndReadAloud() throws {
        let rebuilding = try app(gain: 0.5, enforcement: .recovering)

        #expect(rebuilding.isRecovering)
        #expect(!rebuilding.isIntentUnmet)
        #expect(AudioAppColumn.accessibilityValue(of: rebuilding, isReadOnly: false) == "50%, Recovering")
    }

    @Test
    func theOutputButtonSpeaksForWhereTheAppPlaysOrTheSystemsOutput() throws {
        let following = try app()
        let pinned    = try app(outputUIDs: ["b"], effective: ["b", "a"])

        #expect(AudioAppColumn.shownOutputUIDs(of: following, system: system(selected: ["a"])) == ["a"])
        #expect(AudioAppColumn.shownOutputUIDs(of: pinned, system: system(selected: ["a"])) == ["b", "a"])
    }

    @Test
    func anIconLoadsOnceAndAMissingAppStaysAPlaceholder() async {
        let calls = Mutex(0)
        let cache = AudioAppIconCache { bundleID in
            calls.withLock { $0 += 1 }

            return bundleID == "com.apple.Music" ? NSImage(size: NSSize(width: 18, height: 18)) : nil
        }

        #expect(cache.icon(for: "com.apple.Music") == nil)

        await cache.load("com.apple.Music")
        await cache.load("com.apple.Music")
        await cache.load("com.missing.App")
        await cache.load("com.missing.App")

        #expect(cache.icon(for: "com.apple.Music") != nil)
        #expect(cache.icon(for: "com.missing.App") == nil)
        #expect(calls.withLock { $0 } == 2)
    }
}
