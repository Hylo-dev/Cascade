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
        #expect(AudioOutputIcon.resolve(output: nil, level: -0.2, isMuted: false) == .muted)
        #expect(AudioOutputIcon.resolve(output: airPods, level: 0, isMuted: false) == .muted)
        #expect(AudioOutputIcon.resolve(output: builtIn, level: 0.004, isMuted: false) == .muted)
    }

    @Test
    func theSpeakerShowsAWaveForEachThirdTheLevelReaches() {
        #expect(AudioOutputIcon.speakerWaveCount(level: 0) == 0)
        #expect(AudioOutputIcon.speakerWaveCount(level: 1) == 1)
        #expect(AudioOutputIcon.speakerWaveCount(level: 33) == 1)
        #expect(AudioOutputIcon.speakerWaveCount(level: 34) == 2)
        #expect(AudioOutputIcon.speakerWaveCount(level: 66) == 2)
        #expect(AudioOutputIcon.speakerWaveCount(level: 67) == 3)
        #expect(AudioOutputIcon.speakerWaveCount(level: 100) == 3)
    }

    @Test
    func eachWaveCountHasItsSymbol() {
        #expect(AudioOutputIcon.speakerSymbol(waves: 0) == "speaker.fill")
        #expect(AudioOutputIcon.speakerSymbol(waves: 1) == "speaker.wave.1.fill")
        #expect(AudioOutputIcon.speakerSymbol(waves: 2) == "speaker.wave.2.fill")
        #expect(AudioOutputIcon.speakerSymbol(waves: 3) == "speaker.wave.3.fill")
        #expect(AudioOutputIcon.speakerSymbol(waves: 7) == "speaker.wave.3.fill")
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
        model.receive(state(level: 0.8))
        model.receive(state(level: 0.2))

        #expect(model.system?.level == 0.2) // confirmed, so the next reading is taken whole
    }

    @Test
    func aLateEchoAfterTheDragDoesNotPullTheLevelBack() {
        var time  = ContinuousClock.now
        let model = AudioMixerModel(
            controller: RecordingSystemAudioController(),
            apps      : nil,
            now       : { time }
        )
        model.receive(state(level: 0))

        model.adjust(to: 0.4)
        model.endAdjusting()
        model.receive(state(level: 0))      // the echo of a level sent mid-drag

        #expect(model.system?.level == 0.4)

        time += AudioMixerModel.settleWindow
        model.receive(state(level: 0.1))    // the window has closed: the system wins

        #expect(model.system?.level == 0.1)
    }

    @Test
    func aConfirmingReadingEndsTheSettleAtOnce() {
        let model = AudioMixerModel(controller: RecordingSystemAudioController())
        model.receive(state(level: 0))

        model.adjust(to: 0.4)
        model.endAdjusting()
        model.receive(state(level: 0.41))   // rounded by the system, still a confirmation
        model.receive(state(level: 0.7))    // a change made elsewhere, e.g. the keyboard

        #expect(model.system?.level == 0.7)
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
    func movingTheLevelOfAMutedSystemUnmutesItOnce() {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(isMuted: true, deviceID: 7))

        model.adjust(to: 0.6)
        model.adjust(to: 0.7)

        #expect(controller.mutes == [false])
        #expect(controller.muteTargets == [7])
        #expect(model.system?.isMuted == false)
    }

    @Test
    func aLateMutedReadingDuringADragDoesNotMuteTheCapsuleAgain() {
        let controller = RecordingSystemAudioController()
        let model      = AudioMixerModel(controller: controller)
        model.receive(state(isMuted: true, deviceID: 7))

        model.adjust(to: 0.6)
        model.receive(state(level: 0.2, isMuted: true, deviceID: 7))

        #expect(model.system?.isMuted == false)
        #expect(model.system?.level == 0.6)
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

    // MARK: - Apps

    private func appsModel(
        _ apps        : [AudioAppSnapshot],
        captureAllowed: Bool? = nil
    ) throws -> (AudioMixerModel, RecordingAudioAppsController) {
        let controller = RecordingAudioAppsController()
        let model      = AudioMixerModel(
            controller: RecordingSystemAudioController(),
            apps      : controller
        )
        model.receive(state())
        model.receive(try AudioAppFixture.snapshot(apps, captureAllowed: captureAllowed))

        return (model, controller)
    }

    @Test
    func appsArriveSortedAndLeave() throws {
        let (model, _) = try appsModel(
            [
                try AudioAppFixture.app("com.zed.Zed", name: "Zed"),
                try AudioAppFixture.app("com.apple.Music", name: "Music"),
                try AudioAppFixture.app("com.apple.Safari", name: "safari"),
            ]
        )

        #expect(model.apps.map(\.displayName) == ["Music", "safari", "Zed"])

        model.receive(try AudioAppFixture.snapshot([try AudioAppFixture.app("com.zed.Zed", name: "Zed")], generation: 2))

        #expect(model.apps.map(\.displayName) == ["Zed"])

        model.receive(try AudioAppFixture.snapshot([], generation: 3))

        #expect(model.apps.isEmpty)
    }

    @Test
    func appGainCoalescesToOneCommandPerFrame() async throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel([try AudioAppFixture.app("com.apple.Music", name: "Music")])

        model.adjust(app: music, to: 0.8)
        model.adjust(app: music, to: 0.5)
        model.adjust(app: music, to: 0.25)

        #expect(apps.intents.isEmpty)
        #expect(model.apps.first?.intent.gain == 0.25)
        #expect(model.adjustingApp == music)

        await settleMainQueue()

        #expect(apps.intents.map(\.gain) == [0.25])
        #expect(apps.intentTargets == [music])
    }

    @Test
    func endAdjustingAnAppSendsAtOnceAndStopsAdjusting() async throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel([try AudioAppFixture.app("com.apple.Music", name: "Music")])

        model.adjust(app: music, to: 1.7)
        model.adjust(app: music, to: 0.4)
        model.endAdjusting(app: music)

        #expect(apps.intents.map(\.gain) == [0.4])
        #expect(model.adjustingApp == nil)

        await settleMainQueue()

        #expect(apps.intents.count == 1)
    }

    @Test
    func snapshotsDoNotFightAnAppDrag() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, _)    = try appsModel([try AudioAppFixture.app("com.apple.Music", name: "Music")])

        model.adjust(app: music, to: 0.3)
        model.receive(
            try AudioAppFixture.snapshot(
                [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.9), enforcement: .applied)],
                generation: 2
            )
        )

        #expect(model.apps.first?.intent.gain == 0.3)
        #expect(model.apps.first?.enforcement == .applied)

        model.endAdjusting(app: music)
        model.receive(
            try AudioAppFixture.snapshot(
                [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.9), enforcement: .applied)],
                generation: 3
            )
        )

        #expect(model.apps.first?.intent.gain == 0.9)
    }

    @Test
    func muteKeepsTheGainAndSendsAtOnce() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.4), enforcement: .applied)]
        )

        model.toggleMute(app: music)

        #expect(apps.intents == [try AudioAppFixture.intent(gain: 0.4, isMuted: true)])
        #expect(model.apps.first?.intent.isMuted == true)

        model.toggleMute(app: music)

        #expect(apps.intents.last == (try AudioAppFixture.intent(gain: 0.4)))
    }

    @Test
    func movingTheGainOfAMutedAppUnmutesIt() async throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.4, isMuted: true), enforcement: .applied)]
        )

        model.adjust(app: music, to: 0.6)
        model.endAdjusting(app: music)
        await settleMainQueue()

        #expect(model.apps.first?.intent.isMuted == false)
        #expect(apps.intents.last == (try AudioAppFixture.intent(gain: 0.6)))
    }

    @Test
    func followSystemClearsTheOutputs() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.5, outputUIDs: ["b"]), enforcement: .applied)]
        )

        model.choose(outputUID: nil, for: music)

        #expect(apps.intents == [try AudioAppFixture.intent(gain: 0.5)])
        #expect(model.apps.first?.intent.outputUIDs == [])
    }

    @Test
    func singleModeMakesTheChosenOutputTheAppsOnly() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(outputUIDs: ["a", "b"]), enforcement: .applied)]
        )

        model.choose(outputUID: "c", for: music)

        #expect(apps.intents.map(\.outputUIDs) == [["c"]])
    }

    @Test
    func severalModeNeverEmptiesItFallsBackToFollowSystem() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel([try AudioAppFixture.app("com.apple.Music", name: "Music")])
        model.allowsSeveralOutputs = true

        model.choose(outputUID: "a", for: music)
        model.choose(outputUID: "b", for: music)
        model.choose(outputUID: "a", for: music)
        model.choose(outputUID: "b", for: music)

        #expect(apps.intents.map(\.outputUIDs) == [["a"], ["a", "b"], ["b"], []])
        #expect(model.apps.first?.intent.isNeutral == true)
    }

    @Test
    func severalModeStopsAtTheContractsLimit() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let full          = (0..<AudioAppIntent.maximumOutputs).map { "out\($0)" }
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(outputUIDs: full), enforcement: .applied)]
        )
        model.allowsSeveralOutputs = true

        model.choose(outputUID: "extra", for: music)

        #expect(apps.intents.isEmpty)
        #expect(model.apps.first?.intent.outputUIDs == full)
    }

    @Test
    func returnToNativeForgetsTheIntent() async throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.2), enforcement: .notApplied)]
        )

        model.adjust(app: music, to: 0.1)
        model.returnToNative(app: music)
        await settleMainQueue()

        #expect(apps.returned == [music])
        #expect(apps.intents.isEmpty)
        #expect(model.apps.first?.intent.isNeutral == true)
    }

    @Test
    func captureDeniedRefusesEveryAppCommand() async throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music")],
            captureAllowed: false
        )

        model.adjust(app: music, to: 0.1)
        model.toggleMute(app: music)
        model.choose(outputUID: "a", for: music)
        await settleMainQueue()

        #expect(model.areAppsReadOnly)
        #expect(apps.intents.isEmpty)
        #expect(model.apps.first?.intent.isNeutral == true)
    }

    @Test
    func unknownCaptureIsTreatedAsAllowed() throws {
        let music         = try AudioAppFixture.identity("com.apple.Music")
        let (model, apps) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music")],
            captureAllowed: nil
        )

        model.toggleMute(app: music)

        #expect(!model.areAppsReadOnly)
        #expect(apps.intents.count == 1)
    }

    @Test
    func hostHealthMarksTheAppsAndForgetsThemWhenIdle() throws {
        let (model, _) = try appsModel(
            [try AudioAppFixture.app("com.apple.Music", name: "Music", intent: try AudioAppFixture.intent(gain: 0.4), enforcement: .applied)]
        )

        model.receive(health: .running)

        #expect(model.apps.first?.enforcement == .applied)

        model.receive(health: .recovering)

        #expect(model.apps.first?.enforcement == .recovering)

        model.receive(health: .givenUp)

        #expect(model.apps.first?.enforcement == .native)
        #expect(model.apps.first?.isIntentUnmet == true)

        model.receive(health: .idle)

        #expect(model.apps.isEmpty)
    }

    @Test
    func theMixerVisibilityReachesTheService() throws {
        let (model, apps) = try appsModel([])

        model.setMixerVisible(true)
        model.setMixerVisible(false)

        #expect(apps.visibility == [true, false])
    }
}
