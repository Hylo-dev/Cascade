//
//  NowPlayingProviderStatus.swift
//  Cascade
//

import AppKit
import CascadeKit
import Foundation
import Observation

/// NowPlayingProviderStatus distinguishes no active track from a permission or
/// source failure. An idle, healthy provider remains in the monitoring state.
nonisolated enum NowPlayingProviderStatus: Equatable, Sendable {
    case stopped
    case monitoring
    case unavailable(String)
    case permissionRequired(String)
}
