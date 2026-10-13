//
//  AudioHostWatchdog.swift
//  CascadeKit
//

import CascadeContracts

/// AudioHostWatchdog tells a live pipeline from a stalled one by watching its callback count.
///
/// A device that vanished, a tap the system revoked or a sleep that left the IOProc dead all end
/// the same way: the pipeline still exists and still looks running, but the render callback no
/// longer fires. Nothing else reports that, so the service samples every running pipeline once a
/// second and feeds the samples here. The watchdog is a value-type reducer like the reconciler:
/// no clock, no timer, no HAL, which makes the rule a plain unit test.
///
/// The rule: a sample is stale when the count did not move since the previous sample of the same
/// pipeline while its app still runs output, and two stale samples in a row are a stall. The
/// first sample of a pipeline is only a baseline, never stale, so a device that is still starting
/// is not blamed; the price is that a stall is noticed on the third tick, about three seconds
/// after it began. A pipeline that disappears from the samples is forgotten at once, so a
/// rebuilt one (new token) starts from a fresh baseline.
struct AudioHostWatchdog: Sendable {

    /// The stale samples in a row that make a stall.
    static let staleTicksBeforeRecovery = 2

    /// Sample is one running pipeline as the service saw it at one tick.
    struct Sample: Equatable, Sendable {

        let identity       : AudioAppIdentity
        let token          : UInt64
        let callbackCount  : UInt64
        let isOutputActive : Bool
    }

    /// Stall names a pipeline that stopped rendering.
    struct Stall: Equatable, Sendable {

        let identity : AudioAppIdentity
        let token    : UInt64
    }

    private struct Observation: Sendable {

        let token      : UInt64
        var lastCount  : UInt64
        var staleTicks : Int
    }

    private var observations: [AudioAppIdentity: Observation] = [:]

    /// Folds one round of samples in and returns the pipelines that stalled, ordered by bundle ID.
    /// A stalled pipeline is forgotten: the caller tears it down, and whatever replaces it is a
    /// new token with its own baseline.
    mutating func tick(_ samples: [Sample]) -> [Stall] {
        var stalls : [Stall]                             = []
        var next   : [AudioAppIdentity: Observation]     = [:]

        for sample in samples {
            guard
                var observation = observations[sample.identity],
                observation.token == sample.token
            else {
                next[sample.identity] = Observation(
                    token      : sample.token,
                    lastCount  : sample.callbackCount,
                    staleTicks : 0
                )
                continue
            }

            let isStale = sample.callbackCount == observation.lastCount && sample.isOutputActive

            observation.staleTicks = isStale ? observation.staleTicks + 1 : 0
            observation.lastCount  = sample.callbackCount

            if observation.staleTicks >= Self.staleTicksBeforeRecovery {
                stalls.append(Stall(identity: sample.identity, token: sample.token))
            } else {
                next[sample.identity] = observation
            }
        }

        observations = next

        return stalls.sorted { $0.identity.bundleID < $1.identity.bundleID }
    }
}
