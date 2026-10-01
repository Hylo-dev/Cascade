//
//  PluginExecutionResult.swift
//  CascadeKit
//

import CascadeContracts

/// PluginExecutionResult is an executor's report on one dispatch: what became of it and the CPU
/// time the plugin's thread spent on it. A dispatch ends with the plugin's output. It fails when
/// `handle()` threw, could not run, or its host crashed inside it, which counts against the
/// plugin. It is lost when the kernel itself killed the host or the host was not there, which
/// counts against nobody.
public struct PluginExecutionResult: Sendable {

    /// Outcome is what became of the dispatch.
    public enum Outcome: Equatable, Sendable {

        case output(PluginOutput)
        case failed
        case lost
    }

    public static let lost = PluginExecutionResult(outcome: .lost, cpuTime: .zero)

    public let outcome: Outcome
    public let cpuTime: Duration

    public var output: PluginOutput? {
        guard case .output(let output) = outcome else { return nil }

        return output
    }

    public init(
        outcome: Outcome,
        cpuTime: Duration
    ) {
        self.outcome = outcome
        self.cpuTime = cpuTime
    }

    /// init(output:cpuTime:) reports an output, or a failure when there is none.
    public init(
        output : PluginOutput?,
        cpuTime: Duration
    ) {
        self.init(outcome: output.map(Outcome.output) ?? .failed, cpuTime: cpuTime)
    }
}
