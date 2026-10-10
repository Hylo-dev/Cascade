//
//  SystemAudioServiceTests.swift
//  CascadeTests
//

import CascadeContracts
import CascadeKit
import CoreAudio
import Foundation
import Testing
@testable import Cascade

@MainActor
struct SystemAudioServiceTests {

    private static let builtIn = AudioOutputDevice(
        uid          : "BuiltInSpeakerDevice",
        name         : "MacBook Pro Speakers",
        transportType: kAudioDeviceTransportTypeBuiltIn,
        bluetooth    : nil
    )

    private static let airPodsUID = "a0-1b-2c-3d-4e-f5:output"

    private static let airPods = AudioOutputDevice(
        uid          : airPodsUID,
        name         : "AirPods Pro",
        transportType: kAudioDeviceTransportTypeBluetooth,
        bluetooth    : nil
    )

    private let queue    = DispatchQueue(label: "CascadeTests.SystemAudio")
    private let hardware = FakeSystemAudioHardware()

    private func makeService() -> SystemAudioService {
        SystemAudioService(
            hardware: hardware,
            queue   : queue
        )
    }

    /// settle waits for everything the service queued: the audio queue first, then the main-queue
    /// hop that queue work posts. Neither wait is a sleep.
    private func settle() async {
        queue.sync {}
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// The fire helpers play a hardware listener, which runs on the service's queue. They post
    /// with `async`: `sync` from the main thread may run its block on the main thread.
    private func fireDevicesChangeOnTheQueue() {
        let hardware = hardware
        queue.async { hardware.fireDevicesChange() }
    }

    private func fireVolumeChangeOnTheQueue() {
        let hardware = hardware
        queue.async { hardware.fireVolumeChange() }
    }

    private func playBuiltInAsDefault() {
        hardware.edit {
            $0.devices       = [Self.builtIn, Self.airPods]
            $0.defaultOutput = (7, "BuiltInSpeakerDevice")
            $0.volumes[7]    = .init(level: 0.4, isMuted: false)
        }
    }

    private func bluetoothState(
        deviceID : String,
        model    : PluginBluetoothDeviceModel,
        productID: UInt16? = nil,
        colorID  : UInt8? = nil
    ) -> PluginBluetoothState {
        PluginBluetoothState(
            deviceID   : deviceID,
            name       : "AirPods Pro",
            symbolName : "airpodspro",
            isConnected: true,
            battery    : nil,
            model      : model,
            productID  : productID,
            colorID    : colorID,
            eventID    : 1,
            revision   : 0,
            kind       : .connection,
            isAvailable: true
        )
    }

    @Test
    func startPublishesTheDefaultOutputsLevelAndDevices() async {
        playBuiltInAsDefault()
        let service = makeService()

        service.start()
        await settle()

        #expect(service.model.system == SystemAudioState(
            level          : 0.4,
            isMuted        : false,
            supportsVolume : true,
            outputs        : [Self.builtIn, Self.airPods],
            selectedUIDs   : ["BuiltInSpeakerDevice"],
            defaultDeviceID: 7
        ))
    }

    @Test
    func startingTwiceListensOnce() async {
        playBuiltInAsDefault()
        let service = makeService()

        service.start()
        service.start()
        await settle()

        #expect(hardware.read { $0.listenCount } == 1)
    }

    @Test
    func stoppingStopsListeningAndLaterChangesPublishNothing() async {
        playBuiltInAsDefault()
        let service = makeService()
        service.start()
        await settle()

        service.stop()
        await settle()
        hardware.edit { $0.volumes[7] = .init(level: 0.9, isMuted: false) }
        hardware.fireDevicesChange()
        hardware.fireVolumeChange()
        await settle()

        #expect(hardware.read { $0.stopCount } == 1)
        #expect(service.model.system?.level == 0.4)
    }

    @Test
    func defaultOutputSwitchUpdatesTheModelAndIcon() async {
        hardware.edit {
            $0.devices       = [Self.builtIn, Self.airPods]
            $0.defaultOutput = (9, Self.airPodsUID)
            $0.volumes[9]    = .init(level: 0.7, isMuted: false)
        }
        let service = makeService()
        service.start()
        await settle()
        #expect(service.model.system?.selectedUIDs == [Self.airPodsUID])

        hardware.edit {
            $0.devices       = [Self.builtIn]
            $0.defaultOutput = (7, "BuiltInSpeakerDevice")
            $0.volumes[7]    = .init(level: 0.4, isMuted: false)
        }
        fireDevicesChangeOnTheQueue()
        await settle()

        let system = service.model.system
        #expect(system?.selectedUIDs == ["BuiltInSpeakerDevice"])
        #expect(system?.defaultDeviceID == 7)
        #expect(system?.outputs == [Self.builtIn])
        #expect(system?.level == 0.4)
    }

    @Test
    func staleDeviceCommandIsDropped() async {
        hardware.edit {
            $0.devices       = [Self.builtIn, Self.airPods]
            $0.defaultOutput = (9, Self.airPodsUID)
            $0.volumes[9]    = .init(level: 0.7, isMuted: false)
        }
        let service = makeService()
        service.start()
        await settle()

        service.setLevel(0.2, forDevice: 7)
        service.setMuted(true, forDevice: 7)
        await settle()

        #expect(hardware.read { $0.setVolumeCalls.isEmpty })
        #expect(hardware.read { $0.setMutedCalls.isEmpty })

        service.setLevel(0.2, forDevice: 9)
        service.setMuted(true, forDevice: 9)
        await settle()

        #expect(hardware.read { $0.setVolumeCalls.map(\.deviceID) } == [9])
        #expect(hardware.read { $0.setMutedCalls.map(\.deviceID) } == [9])
    }

    @Test
    func bluetoothIdentityIsAttachedByAddress() async {
        hardware.edit {
            $0.devices       = [Self.builtIn, Self.airPods]
            $0.defaultOutput = (9, Self.airPodsUID)
            $0.volumes[9]    = .init(level: 0.7, isMuted: false)
        }
        let service = makeService()
        service.start()
        await settle()

        service.receive(bluetoothState(
            deviceID : "A0-1B-2C-3D-4E-F5",
            model    : .airPodsPro,
            productID: 0x2014,
            colorID  : 2
        ))

        let device = service.model.system?.outputs.first { $0.uid == Self.airPodsUID }
        #expect(device?.bluetooth?.model == .airPodsPro)
        #expect(device?.bluetooth?.productID == 0x2014)
        #expect(device?.bluetooth?.colorID == 2)
        #expect(service.model.system?.outputs.first { $0.uid == Self.builtIn.uid }?.bluetooth == nil)
    }

    @Test
    func bluetoothIdentityKnownBeforeTheFirstSnapshotIsAttachedToIt() async {
        hardware.edit {
            $0.devices       = [Self.airPods]
            $0.defaultOutput = (9, Self.airPodsUID)
            $0.volumes[9]    = .init(level: 0.7, isMuted: false)
        }
        let service = makeService()
        service.receive(bluetoothState(deviceID: "A0-1B-2C-3D-4E-F5", model: .airPodsPro))

        service.start()
        await settle()

        #expect(service.model.system?.outputs.first?.bluetooth?.model == .airPodsPro)
    }

    @Test
    func aBluetoothStateThatSaysNothingKeepsTheIdentityAlreadyKnown() async {
        hardware.edit {
            $0.devices       = [Self.airPods]
            $0.defaultOutput = (9, Self.airPodsUID)
            $0.volumes[9]    = .init(level: 0.7, isMuted: false)
        }
        let service = makeService()
        service.start()
        await settle()
        service.receive(bluetoothState(deviceID: "A0-1B-2C-3D-4E-F5", model: .airPodsPro))

        service.receive(bluetoothState(deviceID: "A0-1B-2C-3D-4E-F5", model: .generic))

        #expect(service.model.system?.outputs.first?.bluetooth?.model == .airPodsPro)
    }

    @Test
    func multiOutputAggregateIsHiddenFromOutputsAndExpandedToItsSubDevices() async {
        let aggregate = AudioOutputDevice(
            uid          : "cascade.multi-output.x",
            name         : "Cascade Multi-Output",
            transportType: kAudioDeviceTransportTypeAggregate,
            bluetooth    : nil
        )
        hardware.edit {
            $0.devices                = [Self.builtIn, Self.airPods, aggregate]
            $0.defaultOutput          = (20, "cascade.multi-output.x")
            $0.volumes[20]            = .init(level: 0.5, isMuted: false)
            $0.aggregateSubDevices["cascade.multi-output.x"] = [Self.airPodsUID, "BuiltInSpeakerDevice"]
        }
        let service = makeService()

        service.start()
        await settle()

        let system = service.model.system
        #expect(system?.outputs == [Self.builtIn, Self.airPods])
        #expect(system?.selectedUIDs == [Self.airPodsUID, "BuiltInSpeakerDevice"])
        #expect(system?.defaultDeviceID == 20)
    }

    @Test
    func selectingOneOutputMakesItTheDefault() async {
        playBuiltInAsDefault()
        let service = makeService()
        service.start()
        await settle()

        service.selectOutputs([Self.airPodsUID])
        await settle()

        #expect(hardware.read { $0.setDefaultCalls } == [Self.airPodsUID])
    }

    @Test
    func noHardwareCallOnTheMainThread() async {
        playBuiltInAsDefault()
        let service = makeService()

        service.start()
        await settle()
        service.setLevel(0.3, forDevice: 7)
        service.setMuted(true, forDevice: 7)
        service.selectOutputs([Self.airPodsUID])
        service.receive(bluetoothState(deviceID: "A0-1B-2C-3D-4E-F5", model: .airPods))
        fireDevicesChangeOnTheQueue()
        fireVolumeChangeOnTheQueue()
        await settle()
        service.stop()
        await settle()

        #expect(hardware.read { $0.callCount } > 0)
        #expect(hardware.read { $0.mainThreadCalls } == 0)
    }

    @Test
    func volumeChangeDoesNotReenumerateDevices() async {
        playBuiltInAsDefault()
        let service = makeService()
        service.start()
        await settle()
        let enumerationsAtStart = hardware.read { $0.enumerationCount }

        hardware.edit { $0.volumes[7] = .init(level: 0.8, isMuted: false) }
        fireVolumeChangeOnTheQueue()
        await settle()

        #expect(service.model.system?.level == 0.8)
        #expect(hardware.read { $0.enumerationCount } == enumerationsAtStart)

        hardware.edit { $0.devices = [Self.builtIn] }
        fireDevicesChangeOnTheQueue()
        await settle()

        #expect(hardware.read { $0.enumerationCount } == enumerationsAtStart + 1)
        #expect(service.model.system?.outputs == [Self.builtIn])
    }

    /// The model's `system` is Equatable, so setting an equal reading is invisible to observation.
    /// These two tests tell a delivery from a skipped one by what the model shows instead: an
    /// optimistic mute the hardware has not confirmed is wiped by any reading that reaches it.
    @Test
    func identicalReadingIsNotRedelivered() async {
        playBuiltInAsDefault()
        let service = makeService()
        service.start()
        await settle()
        service.model.toggleMute()
        await settle()
        #expect(service.model.system?.isMuted == true)

        fireVolumeChangeOnTheQueue()
        fireDevicesChangeOnTheQueue()
        await settle()
        #expect(service.model.system?.isMuted == true)

        hardware.edit { $0.volumes[7] = .init(level: 0.5, isMuted: false) }
        fireVolumeChangeOnTheQueue()
        await settle()
        #expect(service.model.system?.isMuted == false)
        #expect(service.model.system?.level == 0.5)
    }

    @Test
    func aRefusedWriteRepublishesTheReadingEvenIfNothingChanged() async {
        playBuiltInAsDefault()
        let service = makeService()
        service.start()
        await settle()
        hardware.edit { $0.refusesWrites = true }

        service.model.toggleMute()
        await settle()

        #expect(hardware.read { $0.setMutedCalls.count } == 1)
        #expect(service.model.system?.isMuted == false)
    }

    // MARK: - Multi-output

    private static let usbUID = "AppleUSBAudioEngine:usb"

    private static let usb = AudioOutputDevice(
        uid          : usbUID,
        name         : "USB DAC",
        transportType: kAudioDeviceTransportTypeUSB,
        bluetooth    : nil
    )

    private static let leftoverUID = "cascade.multi-output.old"

    private static let leftover = AudioOutputDevice(
        uid          : leftoverUID,
        name         : "Cascade Multi-Output",
        transportType: kAudioDeviceTransportTypeAggregate,
        bluetooth    : nil
    )

    /// playThreeOutputs gives the fake three real devices with HAL ids, the built-in one playing.
    private func playThreeOutputs() {
        hardware.edit {
            $0.devices       = [Self.builtIn, Self.airPods, Self.usb]
            $0.deviceIDs     = [Self.builtIn.uid: 7, Self.airPodsUID: 9, Self.usbUID: 11]
            $0.defaultOutput = (7, Self.builtIn.uid)
            $0.volumes[7]    = .init(level: 0.4, isMuted: false)
        }
    }

    private func removeDevice(_ uid: String) {
        hardware.edit { $0.devices.removeAll { $0.uid == uid } }
    }

    @Test
    func severalOutputsCreateOneAggregateAndMakeItDefault() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()

        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID])
        await settle()

        let aggregate = "cascade.multi-output.created-0"
        #expect(hardware.read { $0.createdAggregates } == [[Self.builtIn.uid, Self.airPodsUID]])
        #expect(hardware.read { $0.defaultOutput?.uid } == aggregate)
        #expect(hardware.read { $0.operations } == ["create:\(aggregate)", "default:\(aggregate)"])
        #expect(service.model.system?.selectedUIDs == [Self.builtIn.uid, Self.airPodsUID])
        #expect(service.model.system?.outputs == [Self.builtIn, Self.airPods, Self.usb])
    }

    @Test
    func turningSeveralOffLeavesARealDeviceAndDestroysTheAggregate() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID])
        await settle()

        service.selectOutputs([Self.airPodsUID])
        await settle()

        let aggregate = "cascade.multi-output.created-0"
        #expect(hardware.read { $0.defaultOutput?.uid } == Self.airPodsUID)
        #expect(hardware.read { $0.destroyedAggregates } == [aggregate])
        #expect(hardware.read { Array($0.operations.suffix(2)) } == ["default:\(Self.airPodsUID)", "destroy:\(aggregate)"])
        #expect(service.model.system?.selectedUIDs == [Self.airPodsUID])
    }

    @Test
    func changingTheSetReplacesTheAggregate() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID])
        await settle()

        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID, Self.usbUID])
        await settle()

        let first  = "cascade.multi-output.created-0"
        let second = "cascade.multi-output.created-1"
        #expect(hardware.read { $0.createdAggregates.count } == 2)
        #expect(hardware.read { $0.destroyedAggregates } == [first])
        #expect(hardware.read { $0.defaultOutput?.uid } == second)
        #expect(hardware.read { Array($0.operations.suffix(3)) } == ["create:\(second)", "default:\(second)", "destroy:\(first)"])
    }

    @Test
    func aRefusedAggregateLeavesTheCurrentOutputAlone() async {
        playThreeOutputs()
        hardware.edit { $0.refusesCreate = true }
        let service = makeService()
        service.start()
        await settle()

        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID])
        await settle()

        #expect(hardware.read { $0.setDefaultCalls.isEmpty })
        #expect(hardware.read { $0.defaultOutput?.uid } == Self.builtIn.uid)
    }

    @Test
    func launchDestroysLeftoverCascadeAggregates() async {
        playThreeOutputs()
        hardware.edit {
            $0.devices.append(Self.leftover)
            $0.aggregateSubDevices[Self.leftoverUID] = [Self.airPodsUID, Self.builtIn.uid]
            $0.deviceIDs[Self.leftoverUID]           = 20
        }
        let service = makeService()

        service.start()
        await settle()

        #expect(hardware.read { $0.destroyedAggregates } == [Self.leftoverUID])
        #expect(hardware.read { $0.setDefaultCalls.isEmpty })
        #expect(service.model.system?.outputs == [Self.builtIn, Self.airPods, Self.usb])
        #expect(service.model.system?.selectedUIDs == [Self.builtIn.uid])
    }

    @Test
    func leftoverThatIsTheDefaultIsReplacedBeforeItIsDestroyed() async {
        playThreeOutputs()
        hardware.edit {
            $0.devices.append(Self.leftover)
            $0.aggregateSubDevices[Self.leftoverUID] = [Self.airPodsUID, Self.builtIn.uid]
            $0.deviceIDs[Self.leftoverUID]           = 20
            $0.defaultOutput                         = (20, Self.leftoverUID)
        }
        let service = makeService()

        service.start()
        await settle()

        #expect(hardware.read { $0.operations } == ["default:\(Self.airPodsUID)", "destroy:\(Self.leftoverUID)"])
        #expect(hardware.read { $0.defaultOutput?.uid } == Self.airPodsUID)
        #expect(service.model.system?.selectedUIDs == [Self.airPodsUID])
    }

    @Test
    func startingAgainDoesNotTreatTheLiveAggregateAsALeftover() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID])
        await settle()

        service.stop()
        await settle()
        service.start()
        await settle()

        #expect(hardware.read { $0.destroyedAggregates.isEmpty })
        #expect(hardware.read { $0.defaultOutput?.uid } == "cascade.multi-output.created-0")
    }

    @Test
    func quitRestoresTheClockDevice() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.airPodsUID, Self.builtIn.uid])
        await settle()

        service.restoreBeforeQuit()

        let aggregate = "cascade.multi-output.created-0"
        #expect(hardware.read { $0.defaultOutput?.uid } == Self.airPodsUID)
        #expect(hardware.read { $0.destroyedAggregates } == [aggregate])
        #expect(hardware.read { Array($0.operations.suffix(2)) } == ["default:\(Self.airPodsUID)", "destroy:\(aggregate)"])
    }

    @Test
    func quitWithoutAnAggregateTouchesNothing() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()

        service.restoreBeforeQuit()

        #expect(hardware.read { $0.setDefaultCalls.isEmpty })
        #expect(hardware.read { $0.destroyedAggregates.isEmpty })
    }

    @Test
    func losingAllButOneSubDeviceFallsBackToIt() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID, Self.usbUID])
        await settle()
        let aggregate = "cascade.multi-output.created-0"

        removeDevice(Self.usbUID)
        fireDevicesChangeOnTheQueue()
        await settle()

        #expect(hardware.read { $0.destroyedAggregates.isEmpty })
        #expect(hardware.read { $0.defaultOutput?.uid } == aggregate)

        removeDevice(Self.airPodsUID)
        fireDevicesChangeOnTheQueue()
        await settle()

        #expect(hardware.read { $0.defaultOutput?.uid } == Self.builtIn.uid)
        #expect(hardware.read { $0.destroyedAggregates } == [aggregate])
        #expect(hardware.read { Array($0.operations.suffix(2)) } == ["default:\(Self.builtIn.uid)", "destroy:\(aggregate)"])
        #expect(service.model.system?.selectedUIDs == [Self.builtIn.uid])
    }

    @Test
    func losingEverySubDeviceFallsBackToTheBuiltInOutput() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.airPodsUID, Self.usbUID])
        await settle()
        let aggregate = "cascade.multi-output.created-0"

        removeDevice(Self.airPodsUID)
        removeDevice(Self.usbUID)
        fireDevicesChangeOnTheQueue()
        await settle()

        #expect(hardware.read { $0.defaultOutput?.uid } == Self.builtIn.uid)
        #expect(hardware.read { $0.destroyedAggregates } == [aggregate])
    }

    @Test
    func anAggregateThatIsNoLongerTheDefaultIsDestroyed() async {
        playThreeOutputs()
        let service = makeService()
        service.start()
        await settle()
        service.selectOutputs([Self.builtIn.uid, Self.airPodsUID])
        await settle()

        hardware.edit { $0.defaultOutput = (11, Self.usbUID) }
        fireDevicesChangeOnTheQueue()
        await settle()

        #expect(hardware.read { $0.destroyedAggregates } == ["cascade.multi-output.created-0"])
        #expect(hardware.read { $0.defaultOutput?.uid } == Self.usbUID)
    }
}
