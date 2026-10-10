//
//  AudioMixerComponentTests.swift
//  CascadeKit
//

import AppKit
import CoreAudio
import SwiftUI
import Testing
@testable import CascadeKit

/// AudioMixerComponentTests check the mixer's global column and the output selector through the
/// model and the values the views draw from, not through the views themselves: which rows the
/// picker lists, how each is marked, what a choice sends to the system and whether it closes the
/// picker. The views are hosted once, to prove they render.
@MainActor
struct AudioMixerComponentTests {

    private func outputs() -> [AudioOutputDevice] {
        [
            AudioOutputDevice(uid: "a", name: "MacBook Speakers", transportType: kAudioDeviceTransportTypeBuiltIn, bluetooth: nil),
            AudioOutputDevice(uid: "b", name: "Studio Display", transportType: kAudioDeviceTransportTypeDisplayPort, bluetooth: nil),
            AudioOutputDevice(uid: "c", name: "Headset", transportType: kAudioDeviceTransportTypeBluetooth, bluetooth: nil),
        ]
    }

    private func state(
        selected: [String] = ["b"],
        isMuted : Bool = false
    ) -> SystemAudioState {
        SystemAudioState(
            level          : 0.5,
            isMuted        : isMuted,
            supportsVolume : true,
            outputs        : outputs(),
            selectedUIDs   : selected,
            defaultDeviceID: 7
        )
    }

    private func model(
        selected: [String] = ["b"]
    ) -> (AudioMixerModel, RecordingSystemAudioController) {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(selected: selected))

        return (model, controller)
    }

    /// pixels counts what a view draws at more than half opacity; a view that draws nothing
    /// counts zero. Each call hosts the view and caches its display into a bitmap of its own:
    /// `ImageRenderer` hands an empty view the backing store of a previous render, so a view that
    /// draws nothing could read back another test's pixels.
    private func pixels<Content: View>(of view: Content) -> Int {
        let host = NSHostingView(
            rootView: view
                .frame(width: 440, height: 200)
                .environment(\.colorScheme, .dark)
        )
        host.frame = CGRect(x: 0, y: 0, width: 440, height: 200)
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 0 }

        host.cacheDisplay(in: host.bounds, to: bitmap)

        return (0..<bitmap.pixelsWide).reduce(0) { count, x in
            count + (0..<bitmap.pixelsHigh).count { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        }
    }

    @Test
    func mixerShowsTheEmptyAppsStateInThisPart() {
        let (model, _) = model()
        let services   = PluginComponentServices(audio: model)

        #expect(AudioMixerComponent.emptyAppsText == "Apps appear here when they play audio")
        #expect(pixels(of: AudioMixerComponent().environment(\.pluginComponentServices, services)) > 0)
    }

    @Test
    func mixerWithoutAModelDrawsNothingButKeepsRendering() {
        #expect(pixels(of: AudioMixerComponent()) == 0)
    }

    @Test
    func pickerListsEveryOutputAndMarksTheSelection() {
        let (model, _) = model(selected: ["b"])
        let system     = model.system!
        let rows       = AudioOutputPickerRow.rows(
            for                  : system,
            allowsSeveralOutputs : false
        )

        #expect(rows.map(\.uid) == ["a", "b", "c"])
        #expect(rows.filter(\.isSelected).map(\.uid) == ["b"])
        #expect(rows.map(\.marker) == [.none, .checkmark, .none])
        #expect(rows[0].icon == .symbol("macbook"))
        #expect(rows[1].icon == .symbol("display"))
    }

    @Test
    func severalModeMarksEveryRowWithACheckbox() {
        let (model, _) = model(selected: ["a", "c"])
        let rows       = AudioOutputPickerRow.rows(
            for                  : model.system!,
            allowsSeveralOutputs : true
        )

        #expect(rows.map(\.marker) == [.checked, .unchecked, .checked])
    }

    @Test
    func aRowShowsTheDeviceEvenWhenMuted() {
        let muted = SystemAudioState(
            level          : 0,
            isMuted        : true,
            supportsVolume : true,
            outputs        : [AudioOutputDevice(uid: "u", name: "USB", transportType: kAudioDeviceTransportTypeUSB, bluetooth: nil)],
            selectedUIDs   : ["u"],
            defaultDeviceID: 1
        )
        let rows = AudioOutputPickerRow.rows(for: muted, allowsSeveralOutputs: false)

        #expect(rows.map(\.icon) == [.symbol("hifispeaker")])
    }

    @Test
    func singleModeChoiceSelectsAndCloses() {
        let (model, controller) = model()
        var closed              = 0

        AudioOutputPicker.choose(
            "c",
            in     : model,
            onClose: { closed += 1 }
        )

        #expect(controller.selections == [["c"]])
        #expect(closed == 1)
    }

    @Test
    func severalModeChoiceTogglesAndStaysOpen() {
        let (model, controller) = model()
        var closed              = 0
        model.allowsSeveralOutputs = true

        AudioOutputPicker.choose(
            "c",
            in     : model,
            onClose: { closed += 1 }
        )

        #expect(controller.selections == [["b", "c"]])
        #expect(closed == 0)
    }

    @Test
    func theBadgeCountsTheOutputsBeyondTheFirst() {
        #expect(AudioMixerComponent.badge(selectedCount: 1) == nil)
        #expect(AudioMixerComponent.badge(selectedCount: 3) == "+2")
    }

    @Test
    func theMuteButtonTogglesTheSystemMute() {
        let (model, controller) = model()

        #expect(AudioMixerComponent.muteSymbol(isMuted: false) == "speaker.fill")
        #expect(AudioMixerComponent.muteSymbol(isMuted: true) == "speaker.slash.fill")

        model.toggleMute()

        #expect(controller.mutes == [true])
    }

    @Test
    func thePickerRendersAndTheStandaloneComponentIsOffered() {
        let (model, _) = model()
        let services   = PluginComponentServices(audio: model)

        #expect(pixels(of: AudioOutputPicker(model: model, onClose: {})) > 0)
        #expect(
            pixels(
                of: PluginComponentView(id: "audio.outputPicker", version: 1, parameters: [:])
                    .environment(\.pluginComponentServices, services)
            ) > 0
        )
        #expect(
            pixels(
                of: PluginComponentView(id: "audio.mixer", version: 1, parameters: [:])
                    .environment(\.pluginComponentServices, services)
            ) > 0
        )
    }

    @Test
    func theTitleRowFollowsTheNotchObstruction() {
        let notch = CGRect(x: 110, y: 0, width: 180, height: 28)

        #expect(AudioMixerComponent.bandHeight(obstruction: notch) == 28)
        #expect(AudioMixerComponent.titleWidth(obstruction: notch) == 80)
    }

    @Test
    func withoutAnObstructionTheTitleRowSitsAtTheTop() {
        #expect(AudioMixerComponent.bandHeight(obstruction: .zero) == 32)
        #expect(AudioMixerComponent.titleWidth(obstruction: .zero) == nil)
    }
}
