//
//  AudioReconcileAction.swift
//  CascadeKit
//

import CascadeContracts

/// AudioReconcileAction is one thing the reconciler asks AudioHost to do to a pipeline. The
/// reconciler only decides; performing an action is the caller's job, and the caller reports
/// what happened to a build back through `built`.
///
/// A `crossfade` leaves the old pipeline `from` running until `to` is up; once `built` reports
/// success the caller tears `from` down itself, so no separate `teardown` is emitted for it.
/// `scheduleRetry` names a delay on the caller's clock: when it passes, the caller calls
/// `reconcile` again and the reconciler builds if the retry is due.
public enum AudioReconcileAction: Equatable, Sendable {

    case build(AudioAppIdentity, token: UInt64, AudioPipelineConfiguration, AudioAppIntent)
    case crossfade(AudioAppIdentity, from: UInt64, to: UInt64, AudioPipelineConfiguration, AudioAppIntent)
    case updateCommand(AudioAppIdentity, token: UInt64, AudioAppIntent)
    case teardown(AudioAppIdentity, token: UInt64)
    case scheduleRetry(AudioAppIdentity, after: Duration)
}
