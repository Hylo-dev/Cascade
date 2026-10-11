//
//  CoreAudioHostHAL.swift
//  CascadeKit
//

import CascadeAudioRender
import CoreAudio
import Darwin
import Foundation

/// CoreAudioHostHAL is the real `AudioHostHAL`: process taps, private aggregate devices and the
/// C IOProc, over the Core Audio HAL.
///
/// It is confined to the queue it is given. Its mutable state (the IOProc IDs it installed and
/// the listeners it registered) is only touched on that queue, and the HAL delivers every
/// listener block on it, which is the whole reason `@unchecked Sendable` is sound here. The
/// read-only queries hold no state and may be called from anywhere, but production calls them on
/// the queue too.
///
/// Resource notes: nothing here polls. Discovery is one property read per query, and change
/// notification is HAL listeners, which cost nothing while nothing changes. The one buffer it
/// allocates is the 4 KiB path scratch of `processes()`.
final class CoreAudioHostHAL: AudioHostHAL, @unchecked Sendable {

    /// The slice size the kernel is told to expect. It is advisory: `Process` clamps to the
    /// buffers it is really handed, so a device with a larger IO buffer is still rendered whole.
    private static let expectedMaximumFrames: UInt32 = 4096

    private let queue: DispatchQueue

    private var procIDs                : [AudioObjectID: AudioDeviceIOProcID]                 = [:]
    private var systemRegistrations    : [Registration]                                       = []
    private var processRegistrations   : [AudioObjectID: AudioObjectPropertyListenerBlock]    = [:]
    private var onProcessesChanged     : (@Sendable () -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    deinit {
        removeAllListeners()
    }

    // MARK: - Discovery

    func processes() -> [AudioProcessRecord] {
        HALProperty.objectIDs(kAudioHardwarePropertyProcessObjectList).compactMap { objectID in
            guard let pid: Int32 = HALProperty.scalar(kAudioProcessPropertyPID, of: objectID, initial: 0) else {
                return nil
            }

            let bundleID = HALProperty.string(kAudioProcessPropertyBundleID, of: objectID)
            let running  = HALProperty.scalar(kAudioProcessPropertyIsRunningOutput, of: objectID, initial: UInt32(0)) ?? 0

            return AudioProcessRecord(
                objectID        : objectID,
                pid             : pid,
                bundleID        : bundleID?.isEmpty == false ? bundleID : nil,
                executablePath  : Self.executablePath(ofPID: pid),
                isRunningOutput : running != 0
            )
        }
    }

    func outputUIDs() -> Set<String> {
        var uids = Set<String>()

        for device in HALProperty.objectIDs(kAudioHardwarePropertyDevices) {
            let isHidden = HALProperty.scalar(kAudioDevicePropertyIsHidden, of: device, initial: UInt32(0)) ?? 0

            guard
                isHidden == 0,
                !HALProperty.objectIDs(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput, of: device).isEmpty,
                let uid = HALProperty.string(kAudioDevicePropertyDeviceUID, of: device)
            else { continue }

            uids.insert(uid)
        }

        return uids
    }

    func systemOutputUID() -> String? {
        guard
            let device = HALProperty.scalar(
                kAudioHardwarePropertyDefaultOutputDevice,
                of      : AudioObjectID(kAudioObjectSystemObject),
                initial : AudioObjectID(kAudioObjectUnknown)
            ),
            device != kAudioObjectUnknown
        else { return nil }

        return HALProperty.string(kAudioDevicePropertyDeviceUID, of: device)
    }

    func streamFormat(ofOutput uid: String) -> CascadeAudioRenderFormat? {
        guard
            let device = Self.deviceID(forUID: uid),
            let stream = HALProperty.objectIDs(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput, of: device).first,
            let description = HALProperty.scalar(
                kAudioStreamPropertyVirtualFormat,
                of      : stream,
                initial : AudioStreamBasicDescription()
            )
        else { return nil }

        return Self.renderFormat(of: description)
    }

    func outputStreamCount(ofOutput uid: String) -> Int? {
        guard let device = Self.deviceID(forUID: uid) else { return nil }

        return HALProperty.objectIDs(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput, of: device).count
    }

    // MARK: - Taps and aggregates

    func createTap(
        processObjectIDs : [UInt32],
        streamOfOutput   : String?
    ) -> (tapID: UInt32, uuid: String, format: CascadeAudioRenderFormat)? {
        var candidates: [CATapDescription] = []

        if let streamOfOutput {
            candidates.append(CATapDescription(processes: processObjectIDs, deviceUID: streamOfOutput, stream: 0))
        }
        candidates.append(CATapDescription(stereoMixdownOfProcesses: processObjectIDs))

        // A stream tap can be refused where a mixdown works (a device whose first stream is not
        // the one the processes play to), so the mixdown is the fallback, not a failure.
        for description in candidates {
            description.name         = "Cascade"
            description.isPrivate    = true
            description.muteBehavior = .mutedWhenTapped

            var tapID  = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)

            guard status == noErr else { continue }

            guard
                let tapDescription = HALProperty.scalar(kAudioTapPropertyFormat, of: tapID, initial: AudioStreamBasicDescription()),
                let format         = Self.renderFormat(of: tapDescription)
            else {
                AudioHardwareDestroyProcessTap(tapID)
                continue
            }

            return (tapID, description.uuid.uuidString, format)
        }

        return nil
    }

    func createAggregate(
        tapUUID    : String,
        outputUIDs : [String]
    ) -> UInt32? {
        guard let mainOutputUID = outputUIDs.first else { return nil }

        let aggregateUID = "Cascade-\(UUID().uuidString)"

        // The first output is the clock; every other one is resampled against it, which is
        // what keeps stacked devices from drifting apart over a long session.
        let subDevices: [[String: Any]] = outputUIDs.enumerated().map { index, uid in
            index == 0
                ? [kAudioSubDeviceUIDKey: uid]
                : [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: true]
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey          : aggregateUID,
            kAudioAggregateDeviceUIDKey           : aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey : mainOutputUID,
            kAudioAggregateDeviceClockDeviceKey   : mainOutputUID,
            kAudioAggregateDeviceIsPrivateKey     : true,
            kAudioAggregateDeviceIsStackedKey     : outputUIDs.count > 1,
            kAudioAggregateDeviceTapAutoStartKey  : true,
            kAudioAggregateDeviceSubDeviceListKey : subDevices,
            kAudioAggregateDeviceTapListKey       : [[
                kAudioSubTapUIDKey               : tapUUID,
                kAudioSubTapDriftCompensationKey : true,
            ]],
        ]

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status      = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)

        return status == noErr ? aggregateID : nil
    }

    func start(
        aggregate : UInt32,
        render    : OpaquePointer
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))

        // The IOProc is the C trampoline, so no Swift runs on the realtime thread; `render`
        // travels as the client pointer and is freed only after `stop` returns.
        var procID: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcID(
            aggregate,
            CascadeAudioRenderIOProc,
            UnsafeMutableRawPointer(render),
            &procID
        )

        guard created == noErr, let procID else { return false }

        guard AudioDeviceStart(aggregate, procID) == noErr else {
            AudioDeviceDestroyIOProcID(aggregate, procID)
            return false
        }

        procIDs[aggregate] = procID
        return true
    }

    func stop(aggregate: UInt32) {
        dispatchPrecondition(condition: .onQueue(queue))

        guard let procID = procIDs.removeValue(forKey: aggregate) else { return }

        // Both calls block until no IOProc invocation is in flight, which is what makes
        // freeing the render context afterwards safe.
        AudioDeviceStop(aggregate, procID)
        AudioDeviceDestroyIOProcID(aggregate, procID)
    }

    func destroy(aggregate: UInt32) {
        AudioHardwareDestroyAggregateDevice(aggregate)
    }

    func destroy(tap: UInt32) {
        AudioHardwareDestroyProcessTap(tap)
    }

    // MARK: - Listening

    func listen(
        onProcesses      : @escaping @Sendable () -> Void,
        onDevices        : @escaping @Sendable () -> Void,
        onServiceRestart : @escaping @Sendable () -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(queue))

        removeAllListeners()
        onProcessesChanged = onProcesses

        register(kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.processListChanged()
        }
        register(kAudioHardwarePropertyDevices, onChange: onDevices)
        register(kAudioHardwarePropertyDefaultOutputDevice, onChange: onDevices)
        register(kAudioHardwarePropertyServiceRestarted, onChange: onServiceRestart)

        syncProcessListeners()
    }

    /// processListChanged follows the process list: a new process needs its own running-output
    /// listener, a vanished one gives its listener up, and the caller learns about the change.
    private func processListChanged() {
        syncProcessListeners()
        onProcessesChanged?()
    }

    private func syncProcessListeners() {
        let present = Set(HALProperty.objectIDs(kAudioHardwarePropertyProcessObjectList))

        for (objectID, block) in processRegistrations where !present.contains(objectID) {
            var address = HALProperty.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
            processRegistrations[objectID] = nil
        }

        for objectID in present where processRegistrations[objectID] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.onProcessesChanged?()
            }
            var address = HALProperty.address(kAudioProcessPropertyIsRunningOutput)

            if AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr {
                processRegistrations[objectID] = block
            }
        }
    }

    private func register(
        _ selector : AudioObjectPropertySelector,
        onChange   : @escaping @Sendable () -> Void
    ) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        var address = HALProperty.address(selector)

        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
            systemRegistrations.append(Registration(address: address, block: block))
        }
    }

    private func removeAllListeners() {
        for var registration in systemRegistrations {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &registration.address,
                queue,
                registration.block
            )
        }
        systemRegistrations = []

        for (objectID, block) in processRegistrations {
            var address = HALProperty.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        }
        processRegistrations = [:]
    }

    // MARK: - Helpers

    private struct Registration {

        var address : AudioObjectPropertyAddress
        let block   : AudioObjectPropertyListenerBlock
    }

    private static func executablePath(ofPID pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))

        return length > 0 ? String(cString: buffer) : nil
    }

    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = HALProperty.address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID   = uid as CFString
        var device  = AudioObjectID(kAudioObjectUnknown)
        var size    = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                qualifier,
                &size,
                &device
            )
        }

        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// renderFormat maps a Core Audio stream description onto the kernel's format, nil when the
    /// kernel cannot render it. The kernel handles linear PCM floats of 32 or 64 bits, which is
    /// what taps and aggregate devices always present.
    private static func renderFormat(of description: AudioStreamBasicDescription) -> CascadeAudioRenderFormat? {
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0

        guard
            description.mFormatID == kAudioFormatLinearPCM,
            isFloat,
            description.mBitsPerChannel == 32 || description.mBitsPerChannel == 64,
            description.mChannelsPerFrame > 0
        else { return nil }

        return CascadeAudioRenderFormat(
            sampleRate  : description.mSampleRate,
            channels    : description.mChannelsPerFrame,
            interleaved : description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
            float64     : description.mBitsPerChannel == 64,
            maxFrames   : expectedMaximumFrames
        )
    }
}

/// HALProperty reads Core Audio object properties with the boilerplate folded away: an address
/// on the main element, a size query, a typed read. Every read answers nil or empty on any
/// error, because an object that vanished between listing and reading is routine, not exceptional.
private enum HALProperty {

    static func address(
        _ selector : AudioObjectPropertySelector,
        scope      : AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector : selector,
            mScope    : scope,
            mElement  : kAudioObjectPropertyElementMain
        )
    }

    static func objectIDs(
        _ selector : AudioObjectPropertySelector,
        scope      : AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        of object  : AudioObjectID            = AudioObjectID(kAudioObjectSystemObject)
    ) -> [AudioObjectID] {
        var propertyAddress = address(selector, scope: scope)
        var size: UInt32    = 0

        guard
            AudioObjectGetPropertyDataSize(object, &propertyAddress, 0, nil, &size) == noErr,
            size > 0
        else { return [] }

        var identifiers = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)

        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &identifiers) == noErr else {
            return []
        }

        return identifiers
    }

    static func scalar<Value>(
        _ selector : AudioObjectPropertySelector,
        scope      : AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        of object  : AudioObjectID,
        initial    : Value
    ) -> Value? {
        var propertyAddress = address(selector, scope: scope)
        var value           = initial
        var size            = UInt32(MemoryLayout<Value>.size)

        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else {
            return nil
        }

        return value
    }

    static func string(
        _ selector : AudioObjectPropertySelector,
        of object  : AudioObjectID
    ) -> String? {
        var propertyAddress = address(selector)
        var value: Unmanaged<CFString>?
        var size            = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value) == noErr else {
            return nil
        }

        return value?.takeRetainedValue() as String?
    }
}

/// makeCoreAudioHostHAL is the composition root's way to the real HAL. The class stays internal,
/// so its HAL calls are not part of this target's public surface; only the protocol it
/// implements is.
public func makeCoreAudioHostHAL(queue: DispatchQueue) -> any AudioHostHAL {
    CoreAudioHostHAL(queue: queue)
}
