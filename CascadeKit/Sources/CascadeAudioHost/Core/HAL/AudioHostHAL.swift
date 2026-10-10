//
//  AudioHostHAL.swift
//  CascadeKit
//

import CascadeAudioRender

/// AudioHostHAL is AudioHost's whole contact with Core Audio: discovery, taps, aggregate
/// devices and the IOProc that feeds the render kernel. Everything above it (the pipeline, the
/// reconciler's executor) talks to this protocol, so they run in tests against a fake that
/// records calls, and no test ever creates a real tap or needs a permission prompt.
///
/// Every call, `listen`'s callbacks included, happens on the one control queue the concrete HAL
/// was given. Nothing here blocks on the realtime thread: the realtime work is the C kernel,
/// reached through the IOProc `start` installs.
public protocol AudioHostHAL: AnyObject, Sendable {

    /// processes lists every audio process Core Audio knows, running output or not.
    func processes() -> [AudioProcessRecord]

    /// outputUIDs lists the UID of every device that can play audio.
    func outputUIDs() -> Set<String>

    /// systemOutputUID is the UID of the device the system plays to by default, nil when none.
    func systemOutputUID() -> String?

    /// streamFormat is the format of the first output stream of the device `uid`, nil when the
    /// device is gone or has no output stream.
    func streamFormat(ofOutput uid: String) -> CascadeAudioRenderFormat?

    /// createTap taps `processObjectIDs`, muting them while the tap is read.
    ///
    /// With a `streamOfOutput` UID the tap follows what those processes play to that device only
    /// (cheaper, and other devices stay untouched); without one it is a stereo mixdown of
    /// everything they play. The tap is private to this process. `format` is what the tap delivers.
    func createTap(
        processObjectIDs : [UInt32],
        streamOfOutput   : String?
    ) -> (tapID: UInt32, uuid: String, format: CascadeAudioRenderFormat)?

    /// createAggregate wraps the tap and `outputUIDs` in a private aggregate device.
    ///
    /// Several outputs make it stacked, so every device plays the same audio; the first output is
    /// the clock and the others are drift-compensated against it.
    func createAggregate(
        tapUUID    : String,
        outputUIDs : [String]
    ) -> UInt32?

    /// start installs the IOProc that runs `render` on the aggregate and starts the device.
    /// On failure nothing stays installed, so the caller only destroys the aggregate.
    func start(
        aggregate : UInt32,
        render    : OpaquePointer
    ) -> Bool

    /// stop stops the aggregate and removes its IOProc. It returns only once the IOProc is
    /// quiescent, which is what makes destroying the render context afterwards safe.
    func stop(aggregate: UInt32)

    func destroy(aggregate: UInt32)

    func destroy(tap: UInt32)

    /// listen registers the three change notifications, all delivered on the control queue:
    /// the set of audio processes (or any of their running-output flags) changed, the set of
    /// devices or the default output changed, or coreaudiod restarted and every object is gone.
    func listen(
        onProcesses      : @escaping @Sendable () -> Void,
        onDevices        : @escaping @Sendable () -> Void,
        onServiceRestart : @escaping @Sendable () -> Void
    )
}
