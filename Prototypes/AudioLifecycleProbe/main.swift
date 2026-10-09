import CoreAudio
import Foundation

/// Throwaway probe: what does a SIGKILLed process leave behind of Core Audio
/// taps and aggregate devices? Not product code, never linked into Cascade.
///
/// Three modes, one executable, so `run-probe.sh` can kill the creator and
/// then ask a fresh process what survived:
///
///   create-private <pid>   tap (muted when tapped) + private aggregate + IOProc
///   create-public          public stacked aggregate over the default output
///   inspect [--destroy] <uid>...
///
/// The creating modes print one JSON line and then sleep forever. `inspect`
/// prints one JSON document and, with `--destroy`, removes any aggregate it
/// finds so a failed run never leaves a ghost device in the user's Sound menu.

// MARK: - Plumbing

func fail(
    _ message: String,
    status: OSStatus? = nil
) -> Never {
    var payload: [String: Any] = ["error": message]
    if let status { payload["osStatus"] = Int(status) }
    printJSON(payload)
    exit(1)
}

func printJSON(_ object: Any) {
    guard
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
        let text = String(data: data, encoding: .utf8)
    else { return }
    print(text)
    fflush(stdout)
}

func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope   : scope,
        mElement : kAudioObjectPropertyElementMain
    )
}

func objectIDs(
    of selector: AudioObjectPropertySelector,
    on object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)
) -> [AudioObjectID] {
    var propertyAddress = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &propertyAddress, 0, nil, &size) == noErr, size > 0 else { return [] }
    var identifiers = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &identifiers) == noErr else { return [] }
    return identifiers
}

func stringProperty(
    _ selector: AudioObjectPropertySelector,
    on object: AudioObjectID
) -> String? {
    var propertyAddress = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

func defaultOutputDeviceID() -> AudioObjectID {
    var propertyAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &size,
        &device
    )
    guard status == noErr, device != kAudioObjectUnknown else { fail("no default output device", status: status) }
    return device
}

func sleepForever() -> Never {
    while true { sleep(3600) }
}

// MARK: - create-private

/// Process object of `pid`, or exit. The tap is built on process objects, not
/// pids, and an app with no audio client yet has none.
func processObject(for pid: pid_t) -> AudioObjectID {
    var propertyAddress = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        UInt32(MemoryLayout<pid_t>.size),
        &qualifier,
        &size,
        &object
    )
    guard status == noErr, object != kAudioObjectUnknown else { fail("no process object for pid \(pid)", status: status) }
    return object
}

func createPrivate(pid: pid_t) -> Never {
    let outputUID = stringProperty(kAudioDevicePropertyDeviceUID, on: defaultOutputDeviceID()) ?? ""
    let description = CATapDescription(stereoMixdownOfProcesses: [processObject(for: pid)])
    description.name         = "Cascade-probe-tap"
    description.isPrivate    = true
    description.muteBehavior = .mutedWhenTapped

    var tapID = AudioObjectID(kAudioObjectUnknown)
    var status = AudioHardwareCreateProcessTap(description, &tapID)
    guard status == noErr else { fail("AudioHardwareCreateProcessTap", status: status) }

    let aggregateUID = "Cascade-probe-\(UUID().uuidString)"
    let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey         : aggregateUID,
        kAudioAggregateDeviceUIDKey          : aggregateUID,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey    : true,
        kAudioAggregateDeviceIsStackedKey    : false,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
        kAudioAggregateDeviceTapListKey      : [[
            kAudioSubTapUIDKey               : description.uuid.uuidString,
            kAudioSubTapDriftCompensationKey : true,
        ]],
    ]
    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
    guard status == noErr else { fail("AudioHardwareCreateAggregateDevice", status: status) }

    /// The IOProc copies input to output so the muted app is still heard
    /// through the aggregate: without it, "stays muted after the kill" would be
    /// indistinguishable from "was never audible". Unsafe contract: the block
    /// runs on the HAL's IO thread, touches only the two buffer lists it is
    /// handed and allocates nothing.
    var procID: AudioDeviceIOProcID?
    status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inputData, _, outputData, _ in
        let input  = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let output = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: outputData))
        for index in 0 ..< min(input.count, output.count) {
            guard let source = input[index].mData, let destination = output[index].mData else { continue }
            memcpy(destination, source, Int(min(input[index].mDataByteSize, output[index].mDataByteSize)))
        }
    }
    guard status == noErr, let procID else { fail("AudioDeviceCreateIOProcIDWithBlock", status: status) }
    status = AudioDeviceStart(aggregateID, procID)
    guard status == noErr else { fail("AudioDeviceStart", status: status) }

    printJSON([
        "mode"         : "create-private",
        "pid"          : Int(pid),
        "aggregateUID" : aggregateUID,
        "tapUID"       : description.uuid.uuidString,
    ])
    sleepForever()
}

// MARK: - create-public

func createPublic() -> Never {
    let outputUID    = stringProperty(kAudioDevicePropertyDeviceUID, on: defaultOutputDeviceID()) ?? ""
    let aggregateUID = "cascade.multi-output.probe-\(UUID().uuidString)"
    let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey         : aggregateUID,
        kAudioAggregateDeviceUIDKey          : aggregateUID,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey    : false,
        kAudioAggregateDeviceIsStackedKey    : true,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
    ]
    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    let status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
    guard status == noErr else { fail("AudioHardwareCreateAggregateDevice", status: status) }

    printJSON([
        "mode"         : "create-public",
        "aggregateUID" : aggregateUID,
    ])
    sleepForever()
}

// MARK: - inspect

/// Reports, for each UID, whether a device or a tap with that UID is still
/// registered. A private aggregate may be invisible to `kAudioHardwarePropertyDevices`
/// even while alive, so "absent" for a private UID is read together with the
/// tap list and, in the note, with what was audible.
func inspect(
    uids: [String],
    destroy: Bool
) -> Never {
    var deviceByUID: [String: AudioObjectID] = [:]
    for device in objectIDs(of: kAudioHardwarePropertyDevices) {
        if let uid = stringProperty(kAudioDevicePropertyDeviceUID, on: device) { deviceByUID[uid] = device }
    }
    var tapByUID: [String: AudioObjectID] = [:]
    for tap in objectIDs(of: kAudioHardwarePropertyTapList) {
        if let uid = stringProperty(kAudioTapPropertyUID, on: tap) { tapByUID[uid] = tap }
    }

    var destroyed = Set<String>()
    var report: [String: Any] = [:]
    for uid in uids {
        var entry: [String: Any] = [
            "inDevices": deviceByUID[uid] != nil,
            "inTapList": tapByUID[uid] != nil,
        ]
        if destroy {
            if let device = deviceByUID[uid] {
                entry["destroyStatus"] = Int(AudioHardwareDestroyAggregateDevice(device))
                destroyed.insert(uid)
            }
            if let tap = tapByUID[uid] {
                entry["destroyTapStatus"] = Int(AudioHardwareDestroyProcessTap(tap))
            }
        }
        report[uid] = entry
    }

    /// Sweep for leftovers of any earlier run, not just the UIDs asked about.
    let leftovers = deviceByUID.keys.filter { $0.hasPrefix("cascade.multi-output.probe-") || $0.hasPrefix("Cascade-probe-") }
    var leftoverReport: [String: Any] = [:]
    for uid in leftovers.sorted() where !destroyed.contains(uid) {
        guard let device = deviceByUID[uid] else { continue }
        leftoverReport[uid] = destroy ? ["destroyStatus": Int(AudioHardwareDestroyAggregateDevice(device))] : ["present": true]
    }

    printJSON(["uids": report, "leftovers": leftoverReport])
    exit(0)
}

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "create-private":
    guard arguments.count == 2, let pid = pid_t(arguments[1]) else { fail("usage: create-private <pid>") }
    createPrivate(pid: pid)
case "create-public":
    createPublic()
case "inspect":
    var rest = Array(arguments.dropFirst())
    let destroy = rest.first == "--destroy"
    if destroy { rest.removeFirst() }
    inspect(uids: rest, destroy: destroy)
default:
    fail("usage: create-private <pid> | create-public | inspect [--destroy] <uid>...")
}
