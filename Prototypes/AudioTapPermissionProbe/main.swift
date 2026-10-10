import CoreAudio
import Foundation
import Synchronization

/// Throwaway probe: what does a muting process tap do when System Audio
/// Recording is denied, and how do browsers group their audio processes? Not
/// product code, never linked into Cascade.
///
/// Two modes, one executable:
///
///   tap <pid> [seconds]   stereo-mixdown tap (muted when tapped) + private
///                         aggregate + IOProc; prints one JSON line per second
///   processes             every Core Audio process object, as one JSON document
///
/// `tap` answers P1 to P3 (tap creation status, readable signal of a denial,
/// whether the tapped app stays audible). `processes` answers P4 and is
/// read-only: it needs no permission.

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

func uint32Property(
    _ selector: AudioObjectPropertySelector,
    on object: AudioObjectID
) -> UInt32? {
    var propertyAddress = address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else { return nil }
    return value
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

// MARK: - tap

/// Written by the IOProc on the HAL's IO thread, read once per second by the
/// main thread. Atomics, not locks: the IO thread must never wait.
/// `peakBits` holds the bit pattern of a non-negative Float, which orders like
/// the integer, so a compare-exchange loop keeps the maximum.
let callbackCount      = Atomic<Int>(0)
let peakBits           = Atomic<UInt32>(0)
let inputBufferCount   = Atomic<Int>(0)
let lastBufferChannels = Atomic<Int>(0)

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

/// `kAudioTapPropertyFormat` as a plain dictionary, or the OSStatus that
/// refused it: a denial that shows up here is a readable signal (P3).
func tapFormat(of tapID: AudioObjectID) -> [String: Any] {
    var propertyAddress = address(kAudioTapPropertyFormat)
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &size, &format)
    guard status == noErr else { return ["osStatus": Int(status)] }
    return [
        "sampleRate"      : format.mSampleRate,
        "channels"        : Int(format.mChannelsPerFrame),
        "bitsPerChannel"  : Int(format.mBitsPerChannel),
        "formatFlags"     : Int(format.mFormatFlags),
    ]
}

func runTap(
    pid: pid_t,
    seconds: Int
) -> Never {
    let outputUID = stringProperty(kAudioDevicePropertyDeviceUID, on: defaultOutputDeviceID()) ?? ""
    let description = CATapDescription(stereoMixdownOfProcesses: [processObject(for: pid)])
    description.name         = "Cascade-probe-tap"
    description.isPrivate    = true
    description.muteBehavior = .mutedWhenTapped

    var tapID = AudioObjectID(kAudioObjectUnknown)
    var status = AudioHardwareCreateProcessTap(description, &tapID)
    guard status == noErr else { fail("AudioHardwareCreateProcessTap", status: status) }
    let format = tapFormat(of: tapID)

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
    guard status == noErr else {
        _ = AudioHardwareDestroyProcessTap(tapID)
        fail("AudioHardwareCreateAggregateDevice", status: status)
    }

    /// Unsafe contract: the block runs on the HAL's IO thread, touches only the
    /// buffer lists it is handed and the atomics above, and allocates nothing.
    /// An aggregate lists its sub-devices' own input streams first and the
    /// tap's streams last, so the LAST input buffer is the tap. It writes ZEROS
    /// to every output buffer: the tapped app is then silent exactly when the
    /// muting works.
    var procID: AudioDeviceIOProcID?
    status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inputData, _, outputData, _ in
        callbackCount.add(1, ordering: .relaxed)

        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        inputBufferCount.store(input.count, ordering: .relaxed)
        if let tapBuffer = input.last, let samples = tapBuffer.mData?.assumingMemoryBound(to: Float32.self) {
            lastBufferChannels.store(Int(tapBuffer.mNumberChannels), ordering: .relaxed)
            var blockPeak: Float32 = 0
            for index in 0 ..< Int(tapBuffer.mDataByteSize) / MemoryLayout<Float32>.size {
                blockPeak = max(blockPeak, abs(samples[index]))
            }
            let candidate = blockPeak.bitPattern
            var current = peakBits.load(ordering: .relaxed)
            while candidate > current {
                let result = peakBits.compareExchange(expected: current, desired: candidate, ordering: .relaxed)
                if result.exchanged { break }
                current = result.original
            }
        }

        let output = UnsafeMutableAudioBufferListPointer(outputData)
        for index in 0 ..< output.count {
            guard let destination = output[index].mData else { continue }
            memset(destination, 0, Int(output[index].mDataByteSize))
        }
    }
    guard status == noErr, let procID else { fail("AudioDeviceCreateIOProcIDWithBlock", status: status) }
    status = AudioDeviceStart(aggregateID, procID)
    guard status == noErr else { fail("AudioDeviceStart", status: status) }

    for second in 1 ... seconds {
        sleep(1)
        let peak = Float32(bitPattern: peakBits.exchange(0, ordering: .relaxed))
        printJSON([
            "mode"              : "tap",
            "pid"               : Int(pid),
            "second"            : second,
            "tapCreateStatus"   : 0,
            "tapFormat"         : format,
            "callbacks"         : callbackCount.load(ordering: .relaxed),
            "inputBuffers"      : inputBufferCount.load(ordering: .relaxed),
            "tapBufferChannels" : lastBufferChannels.load(ordering: .relaxed),
            "peakThisSecond"    : peak,
            "aggregateUID"      : aggregateUID,
        ])
    }

    _ = AudioDeviceStop(aggregateID, procID)
    _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
    _ = AudioHardwareDestroyAggregateDevice(aggregateID)
    _ = AudioHardwareDestroyProcessTap(tapID)
    exit(0)
}

// MARK: - processes

/// The outermost enclosing `.app` of an executable path: walk from the root
/// and keep the first component ending in `.app`, so a helper nested inside
/// `Foo.app/Contents/Frameworks/.../Helper.app` reports `Foo.app`.
func outermostApp(of executablePath: String) -> String? {
    var accumulated = ""
    for component in executablePath.split(separator: "/") {
        accumulated += "/" + component
        if component.hasSuffix(".app") { return accumulated }
    }
    return nil
}

func executablePath(of pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(cString: buffer)
}

func listProcesses() -> Never {
    var entries: [[String: Any]] = []
    for object in objectIDs(of: kAudioHardwarePropertyProcessObjectList) {
        var entry: [String: Any] = ["objectID": Int(object)]
        if let pid = uint32Property(kAudioProcessPropertyPID, on: object).map({ pid_t(bitPattern: $0) }) {
            entry["pid"] = Int(pid)
            if let path = executablePath(of: pid) {
                entry["executablePath"] = path
                if let app = outermostApp(of: path) { entry["outermostApp"] = app }
            }
        }
        if let bundleID = stringProperty(kAudioProcessPropertyBundleID, on: object) { entry["bundleID"] = bundleID }
        if let running = uint32Property(kAudioProcessPropertyIsRunningOutput, on: object) { entry["isRunningOutput"] = running != 0 }
        entries.append(entry)
    }
    entries.sort { ($0["pid"] as? Int ?? 0) < ($1["pid"] as? Int ?? 0) }
    printJSON(["processes": entries])
    exit(0)
}

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "tap":
    guard (2 ... 3).contains(arguments.count), let pid = pid_t(arguments[1]) else { fail("usage: tap <pid> [seconds]") }
    let seconds = arguments.count == 3 ? Int(arguments[2]) : 5
    guard let seconds, seconds > 0 else { fail("usage: tap <pid> [seconds]") }
    runTap(pid: pid, seconds: seconds)
case "processes":
    listProcesses()
default:
    fail("usage: tap <pid> [seconds] | processes")
}
