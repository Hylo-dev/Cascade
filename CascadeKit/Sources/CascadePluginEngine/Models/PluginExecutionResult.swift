//
//  PluginExecutionResult.swift
//  CascadeKit
//

import CascadeContracts

/// PluginExecutionResult is an executor's report on one dispatch: the plugin's output, or none
/// when `handle()` threw or could not run, and the CPU time its thread spent on it.
public struct PluginExecutionResult: Sendable {

    public let output : PluginOutput?
    public let cpuTime: Duration

    public init(
        output : PluginOutput?,
        cpuTime: Duration
    ) {
        self.output  = output
        self.cpuTime = cpuTime
    }
}
