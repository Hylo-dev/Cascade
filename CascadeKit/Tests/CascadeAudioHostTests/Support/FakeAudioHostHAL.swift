//
//  FakeAudioHostHAL.swift
//  CascadeKit
//

import CascadeAudioHost
import CascadeAudioRender
import Foundation

/// FakeAudioHostHAL is an `AudioHostHAL` that creates nothing and records everything: every
/// call lands in `calls` in order, so a test can assert the exact build and teardown sequence
/// of a pipeline without a single real tap, aggregate device or permission prompt.
///
/// It is single-threaded like the control queue it stands in for; the `@unchecked Sendable`
/// only satisfies the protocol, and no test touches one from two threads.
final class FakeAudioHostHAL: AudioHostHAL, @unchecked Sendable {

    enum Call: Equatable {

        case createTap(processObjectIDs: [UInt32], streamOfOutput: String?)
        case createAggregate(tapUUID: String, outputUIDs: [String])
        case streamFormat(ofOutput: String)
        case start(aggregate: UInt32)
        case stop(aggregate: UInt32)
        case destroyAggregate(UInt32)
        case destroyTap(UInt32)
    }

    static let tapID       : UInt32 = 100
    static let aggregateID : UInt32 = 200
    static let tapUUID     = "fake-tap-uuid"

    static let stereoFloat32 = CascadeAudioRenderFormat(
        sampleRate  : 48_000,
        channels    : 2,
        interleaved : true,
        float64     : false,
        maxFrames   : 4096
    )

    private(set) var calls: [Call] = []

    /// The render context handed to `start`, so a test can push audio through the kernel the
    /// way the IOProc would. It is valid until the pipeline under test is torn down.
    private(set) var startedRender: OpaquePointer?

    var tapFormat          : CascadeAudioRenderFormat? = FakeAudioHostHAL.stereoFloat32
    var outputFormat       : CascadeAudioRenderFormat? = FakeAudioHostHAL.stereoFloat32
    var tapShouldFail      : Bool                      = false
    var aggregateShouldFail: Bool                      = false
    var startShouldFail    : Bool                      = false

    /// Runs inside `destroy(tap:)`, which is where the pipeline must still own its render context.
    var onDestroyTap: (() -> Void)?

    func processes() -> [AudioProcessRecord] {
        []
    }

    func outputUIDs() -> Set<String> {
        []
    }

    func systemOutputUID() -> String? {
        nil
    }

    func streamFormat(ofOutput uid: String) -> CascadeAudioRenderFormat? {
        calls.append(.streamFormat(ofOutput: uid))
        return outputFormat
    }

    func createTap(
        processObjectIDs : [UInt32],
        streamOfOutput   : String?
    ) -> (tapID: UInt32, uuid: String, format: CascadeAudioRenderFormat)? {
        calls.append(.createTap(processObjectIDs: processObjectIDs, streamOfOutput: streamOfOutput))

        guard !tapShouldFail, let tapFormat else { return nil }

        return (Self.tapID, Self.tapUUID, tapFormat)
    }

    func createAggregate(
        tapUUID    : String,
        outputUIDs : [String]
    ) -> UInt32? {
        calls.append(.createAggregate(tapUUID: tapUUID, outputUIDs: outputUIDs))

        return aggregateShouldFail ? nil : Self.aggregateID
    }

    func start(
        aggregate : UInt32,
        render    : OpaquePointer
    ) -> Bool {
        calls.append(.start(aggregate: aggregate))

        guard !startShouldFail else { return false }

        startedRender = render
        return true
    }

    func stop(aggregate: UInt32) {
        calls.append(.stop(aggregate: aggregate))
    }

    func destroy(aggregate: UInt32) {
        calls.append(.destroyAggregate(aggregate))
    }

    func destroy(tap: UInt32) {
        calls.append(.destroyTap(tap))
        onDestroyTap?()
    }

    func listen(
        onProcesses      : @escaping @Sendable () -> Void,
        onDevices        : @escaping @Sendable () -> Void,
        onServiceRestart : @escaping @Sendable () -> Void
    ) {}
}
