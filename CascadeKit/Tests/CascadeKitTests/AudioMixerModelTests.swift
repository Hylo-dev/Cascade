//
//  AudioMixerModelTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreAudio
import Testing
@testable import CascadeKit

@MainActor
struct AudioMixerModelTests {

    private let airPodsIdentity = AudioBluetoothIdentity(
        model    : .airPods,
        productID: 0x2014,
        colorID  : 1
    )

    private func device(
        uid      : String,
        transport: UInt32,
        bluetooth: AudioBluetoothIdentity? = nil
    ) -> AudioOutputDevice {
        AudioOutputDevice(
            uid          : uid,
            name         : uid,
            transportType: transport,
            bluetooth    : bluetooth
        )
    }

    private func state(
        level    : Double = 0.5,
        isMuted  : Bool = false,
        deviceID : UInt32 = 7,
        selected : [String] = ["a"]
    ) -> SystemAudioState {
        SystemAudioState(
            level          : level,
            isMuted        : isMuted,
            supportsVolume : true,
            outputs        : [],
            selectedUIDs   : selected,
            defaultDeviceID: deviceID
        )
    }

    /// settleMainQueue returns after every block already queued on the main queue has run.
    private func settleMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @Test
    func deviceIconNamesTheOutputItself() {
        let builtIn    = device(uid: "built-in", transport: kAudioDeviceTransportTypeBuiltIn)
        let airPods    = device(uid: "pods", transport: kAudioDeviceTransportTypeBluetooth, bluetooth: airPodsIdentity)
        let headset    = device(uid: "headset", transport: kAudioDeviceTransportTypeBluetoothLE)
        let monitor    = device(uid: "dp", transport: kAudioDeviceTransportTypeDisplayPort)
        let television = device(uid: "hdmi", transport: kAudioDeviceTransportTypeHDMI)
        let airPlay    = device(uid: "airplay", transport: kAudioDeviceTransportTypeAirPlay)
        let unknownUSB = device(uid: "usb", transport: kAudioDeviceTransportTypeUSB)

        #expect(AudioOutputIcon.device(for: builtIn) == .symbol("macbook"))
        #expect(AudioOutputIcon.device(for: airPods) == .symbol("airpods"))
        #expect(AudioOutputIcon.device(for: headset) == .symbol("headphones"))
        #expect(AudioOutputIcon.device(for: monitor) == .symbol("display"))
        #expect(AudioOutputIcon.device(for: television) == .symbol("tv"))
        #expect(AudioOutputIcon.device(for: airPlay) == .symbol("airplayaudio"))
        #expect(AudioOutputIcon.device(for: unknownUSB) == .symbol("hifispeaker"))
        #expect(AudioOutputIcon.device(for: nil) == .symbol("hifispeaker"))
    }

    @Test
    func iconFollowsLevelBluetoothAndTransport() {
        let builtIn    = device(uid: "built-in", transport: kAudioDeviceTransportTypeBuiltIn)
        let airPods    = device(uid: "pods", transport: kAudioDeviceTransportTypeBluetooth, bluetooth: airPodsIdentity)
        let unknownUSB = device(uid: "usb", transport: kAudioDeviceTransportTypeUSB)
        let headset    = device(uid: "headset", transport: kAudioDeviceTransportTypeBluetoothLE)
        let monitor    = device(uid: "dp", transport: kAudioDeviceTransportTypeDisplayPort)
        let television = device(uid: "hdmi", transport: kAudioDeviceTransportTypeHDMI)
        let airPlay    = device(uid: "airplay", transport: kAudioDeviceTransportTypeAirPlay)

        #expect(AudioOutputIcon.resolve(output: builtIn, level: 0.5, isMuted: false) == .speaker(level: 50))
        #expect(AudioOutputIcon.resolve(output: airPods, level: 0.5, isMuted: false) == .symbol("airpods"))
        #expect(AudioOutputIcon.resolve(output: unknownUSB, level: 0.2, isMuted: false) == .speaker(level: 20))
        #expect(AudioOutputIcon.resolve(output: airPods, level: 0.5, isMuted: true) == .muted)
        #expect(AudioOutputIcon.resolve(output: headset, level: 0.5, isMuted: false) == .symbol("headphones"))
        #expect(AudioOutputIcon.resolve(output: monitor, level: 0.5, isMuted: false) == .symbol("display"))
        #expect(AudioOutputIcon.resolve(output: television, level: 0.5, isMuted: false) == .symbol("tv"))
        #expect(AudioOutputIcon.resolve(output: airPlay, level: 0.5, isMuted: false) == .symbol("airplayaudio"))
        #expect(AudioOutputIcon.resolve(output: nil, level: 1.4, isMuted: false) == .speaker(level: 100))
        #expect(AudioOutputIcon.resolve(output: nil, level: -0.2, isMuted: false) == .speaker(level: 0))
    }

    @Test
    func adjustingCoalescesToOneCommandWithTheLatestLevel() async {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state())

        model.adjust(to: 0.1)
        model.adjust(to: 0.2)
        model.adjust(to: 0.3)

        #expect(controller.levels.isEmpty)
        #expect(model.system?.level == 0.3)
        #expect(model.isAdjusting)

        await settleMainQueue()

        #expect(controller.levels == [0.3])
        #expect(controller.levelTargets == [7])
    }

    @Test
    func adjustClampsToTheUnitRange() async {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state())

        model.adjust(to: 1.7)
        await settleMainQueue()

        #expect(controller.levels == [1.0])
    }

    @Test
    func endAdjustingFlushesAtOnceAndStopsAdjusting() async {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state())

        model.adjust(to: 0.4)
        model.endAdjusting()

        #expect(controller.levels == [0.4])
        #expect(!model.isAdjusting)

        await settleMainQueue()

        #expect(controller.levels == [0.4])
    }

    @Test
    func serviceStateDoesNotFightAnOngoingDrag() {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(level: 0.5))

        model.adjust(to: 0.8)
        model.receive(state(level: 0.2))

        #expect(model.system?.level == 0.8)

        model.endAdjusting()
        model.receive(state(level: 0.2))

        #expect(model.system?.level == 0.2)
    }

    @Test
    func commandsCarryTheDeviceTheyWereMadeFor() async {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(level: 0.5, deviceID: 7))

        model.adjust(to: 0.8)
        model.receive(state(level: 0.3, deviceID: 9))
        await settleMainQueue()

        #expect(controller.levels.isEmpty)
        #expect(model.system?.defaultDeviceID == 9)
        #expect(model.system?.level == 0.3)
    }

    @Test
    func toggleMuteSendsTheOppositeForTheCurrentDevice() {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(isMuted: false, deviceID: 7))

        model.toggleMute()

        #expect(controller.mutes == [true])
        #expect(controller.muteTargets == [7])
        #expect(model.system?.isMuted == true)
    }

    @Test
    func singleModeSelectsExactlyTheChosenOutput() {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(selected: ["a"]))

        model.choose(outputUID: "b")

        #expect(controller.selections == [["b"]])
        #expect(model.system?.selectedUIDs == ["b"])
    }

    @Test
    func severalModeTogglesButNeverEmpties() {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(selected: []))
        model.allowsSeveralOutputs = true

        model.choose(outputUID: "a")
        model.choose(outputUID: "b")
        model.choose(outputUID: "a")
        model.choose(outputUID: "b")

        #expect(controller.selections == [["a"], ["a", "b"], ["b"]])
        #expect(model.system?.selectedUIDs == ["b"])
    }
}
