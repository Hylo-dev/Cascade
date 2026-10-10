//
//  AudioPipelineState.swift
//  CascadeKit
//

/// AudioPipelineState is where one app's pipeline stands, as the reconciler sees it.
///
/// A token names one build attempt and only grows, so a late answer for an attempt that was
/// replaced is recognised and dropped. `failed` means no pipeline exists and a retry may be
/// pending; `native` means Cascade gave up on this configuration and the app plays untouched
/// until its configuration or intent changes. `since` is when the failure episode began, on the
/// caller's clock, which is what the three-second recovery window is measured from.
public enum AudioPipelineState: Equatable, Sendable {

    case none
    case building(token: UInt64, AudioPipelineConfiguration)
    case running(token: UInt64, AudioPipelineConfiguration)
    case crossfading(from: UInt64, to: UInt64, AudioPipelineConfiguration)
    case failed(AudioPipelineConfiguration, attempts: Int, since: Duration)
    case native(AudioPipelineConfiguration)
}
