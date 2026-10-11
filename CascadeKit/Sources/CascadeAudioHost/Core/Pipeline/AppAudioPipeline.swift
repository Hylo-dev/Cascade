//
//  AppAudioPipeline.swift
//  CascadeKit
//

import CascadeAudioRender
import CascadeContracts

/// AppAudioPipeline is one app's live audio path: a tap on its processes, a private aggregate
/// device that plays the tap to the chosen outputs, and the render kernel that scales it in
/// between. The app's own output is muted while the tap is read, so what the user hears is
/// exactly what the kernel renders: gain, mute and crossfade all happen there.
///
/// Building is all or nothing. `init?` creates the tap, the aggregate, the output format, the
/// render context and finally starts the device, and if any step fails it undoes the steps
/// already done in reverse and returns nil, so a failed build leaves nothing behind. Teardown
/// is the same walk backwards, and its order is the safety property: the device must be stopped
/// (the IOProc quiescent) before the render context its IOProc points at is freed.
///
/// `@unchecked Sendable` is justified by confinement, not by locks: a pipeline lives on the
/// control queue and every call to it, `deinit` included, happens there. The only thing the
/// realtime thread shares with it is the C kernel, which is designed for exactly that.
final class AppAudioPipeline: @unchecked Sendable {

    let identity   : AudioAppIdentity
    let token      : UInt64

    /// sampleRate is the rate of the output the kernel renders to, which is what a crossfade
    /// needs to turn its 50 ms into a frame count.
    let sampleRate : Double

    private let hal         : any AudioHostHAL
    private let tapID       : UInt32
    private let aggregateID : UInt32

    /// The kernel the IOProc renders through. Owned here, freed last by `teardown`.
    private var render: OpaquePointer?

    /// hasRenderContext tells whether the kernel is still alive, which only a test cares about.
    var hasRenderContext: Bool { render != nil }

    /// callbackCount is how many slices the IOProc has rendered, 0 once torn down. The watchdog
    /// reads it to tell a live pipeline from a stalled one.
    var callbackCount: UInt64 {
        guard let render else { return 0 }

        return CascadeAudioRenderCallbackCount(render)
    }

    init?(
        identity      : AudioAppIdentity,
        token         : UInt64,
        configuration : AudioPipelineConfiguration,
        intent        : AudioAppIntent,
        hal           : any AudioHostHAL
    ) {
        guard let mainOutputUID = configuration.outputUIDs.first else { return nil }

        guard let tap = hal.createTap(
            processObjectIDs : configuration.processObjectIDs,
            streamOfOutput   : configuration.streamTap ? mainOutputUID : nil
        ) else { return nil }

        guard let aggregate = hal.createAggregate(
            tapUUID    : tap.uuid,
            outputUIDs : configuration.outputUIDs
        ) else {
            hal.destroy(tap: tap.tapID)
            return nil
        }

        // The aggregate presents the main output's streams, so that device's format is the
        // format the IOProc will be handed on the output side.
        guard
            let outputFormat = hal.streamFormat(ofOutput: mainOutputUID),
            let render       = CascadeAudioRenderCreate(
                tap.format,
                outputFormat,
                intent.gain,
                intent.isMuted
            )
        else {
            hal.destroy(aggregate: aggregate)
            hal.destroy(tap: tap.tapID)
            return nil
        }

        guard hal.start(aggregate: aggregate, render: render) else {
            hal.destroy(aggregate: aggregate)
            hal.destroy(tap: tap.tapID)
            CascadeAudioRenderDestroy(render)
            return nil
        }

        self.identity    = identity
        self.token       = token
        self.sampleRate  = outputFormat.sampleRate
        self.hal         = hal
        self.tapID       = tap.tapID
        self.aggregateID = aggregate
        self.render      = render
    }

    deinit {
        teardown()
    }

    /// update publishes the intent's gain and mute to the kernel, which ramps to them over 5 ms.
    func update(_ intent: AudioAppIntent) {
        guard let render else { return }

        CascadeAudioRenderSetCommand(render, intent.gain, intent.isMuted)
    }

    /// beginCrossfade starts this pipeline's share of an equal-power handover: from silence up
    /// to full when `fadingIn`, from full down to silence otherwise. The caller starts the
    /// opposite fade on the other pipeline in the same step.
    func beginCrossfade(
        fadingIn : Bool,
        frames   : UInt32
    ) {
        guard let render else { return }

        CascadeAudioRenderSetCrossfade(render, fadingIn ? 0 : 1, fadingIn ? 1 : 0, frames)
    }

    /// teardown stops the device, destroys the aggregate, then the tap, then the render
    /// context, and does nothing the second time.
    ///
    /// The order is the contract: `stop` returns only when the IOProc is quiescent, so the
    /// kernel is freed only after the last callback that could touch it.
    func teardown() {
        guard let render else { return }

        hal.stop(aggregate: aggregateID)
        hal.destroy(aggregate: aggregateID)
        hal.destroy(tap: tapID)

        CascadeAudioRenderDestroy(render)
        self.render = nil
    }
}
