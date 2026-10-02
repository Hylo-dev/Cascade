//
//  PluginExecutor+Async.swift
//  CascadeKit
//

import CascadeContracts

@testable import CascadePluginEngine

extension PluginExecutor {

    /// dispatch waits for the executor's report on one event.
    func dispatch(
        _ event  : PluginEvent,
        to plugin: PluginID
    ) async -> PluginExecutionResult {
        await withCheckedContinuation { continuation in
            dispatch(event, to: plugin) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
