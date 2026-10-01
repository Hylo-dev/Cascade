//
//  RefreshSignal.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

/// RefreshSignal is the first thing an observed refresh reports: either a held invocation or a
/// terminal refresh result.
enum RefreshSignal: Sendable {

    case invoked
    case completed(Result<ProviderOutput, any Error>)
}
