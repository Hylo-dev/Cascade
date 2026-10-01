//
//  PluginHostIntegrationTests.swift
//  CascadeTests
//

import CascadeContracts
import CascadePluginEngine
import CascadePluginHost
import Testing

/// PluginHostIntegrationTests drive the real PluginHost bundled in the test host, over XPC, with
/// the probe plugins a Debug PluginHost carries. A restart waits out launchd's ten second floor,
/// so each restart test takes that long.
@Suite(.serialized)
struct PluginHostIntegrationTests {

    private let echo = PluginID(rawValue: "com.cascade.probe.echo")!
    private let hang = PluginID(rawValue: "com.cascade.probe.hang")!
    private let exit = PluginID(rawValue: "com.cascade.probe.exit")!
    private let trap = PluginID(rawValue: "com.cascade.probe.trap")!

    private func executor() -> (SharedHostExecutor, HostEvents) {
        let requirement = PluginHostSigning.requirement(identifier: "hylo.Cascade.PluginHost", team: PluginHostSigning.currentTeam)
        let executor    = SharedHostExecutor(transport: XPCPluginTransport(serviceName: "hylo.Cascade.PluginHost", requirement: requirement))
        let events      = HostEvents()
        executor.observe { events.record($0) }

        return (executor, events)
    }

    private func dispatch(
        _ event    : PluginEvent,
        to plugin  : PluginID,
        on executor: SharedHostExecutor
    ) async -> PluginExecutionResult {
        await withCheckedContinuation { continuation in
            executor.dispatch(event, to: plugin) { continuation.resume(returning: $0) }
        }
    }

    /// host is the PID the echo probe published, which names the PluginHost that ran it.
    private func host(of result: PluginExecutionResult) -> String? {
        guard case .text(let text)? = result.output?.publications.first?.document?.root.kind else { return nil }

        return text
    }

    @Test
    func anEventRoundTripsThroughTheBundledHost() async throws {
        let (executor, events) = executor()
        executor.start(echo, entryPoint: "ProbeEcho")

        #expect(try await events.wait(for: .available, count: 1))
        #expect(host(of: await dispatch(.refresh, to: echo, on: executor)) != nil)
    }

    @Test
    func aHungPluginIsKilledAndTheHostComesBackWithoutIt() async throws {
        let (executor, events) = executor()
        executor.start(echo, entryPoint: "ProbeEcho")
        executor.start(hang, entryPoint: "ProbeHang")
        #expect(try await events.wait(for: .available, count: 1))
        let before = host(of: await dispatch(.refresh, to: echo, on: executor))

        async let stuck = dispatch(.refresh, to: hang, on: executor)
        try await Task.sleep(for: .milliseconds(300))
        executor.stop(hang)

        #expect(await stuck.outcome == .lost)
        #expect(try await events.wait(for: .available, count: 2, within: .seconds(30)))

        let after = host(of: await dispatch(.refresh, to: echo, on: executor))
        #expect(after != nil)
        #expect(after != before)
        #expect(await dispatch(.refresh, to: hang, on: executor).outcome == .failed)
    }

    @Test
    func aHostThatExitsInsideAPluginFailsTheDispatchAndComesBack() async throws {
        let (executor, events) = executor()
        executor.start(echo, entryPoint: "ProbeEcho")
        executor.start(exit, entryPoint: "ProbeExit")
        #expect(try await events.wait(for: .available, count: 1))
        let before = host(of: await dispatch(.refresh, to: echo, on: executor))

        #expect(await dispatch(.refresh, to: exit, on: executor).outcome == .failed)
        #expect(try await events.wait(for: .available, count: 2, within: .seconds(30)))

        let after = host(of: await dispatch(.refresh, to: echo, on: executor))
        #expect(after != nil)
        #expect(after != before)
    }

    /// A real crash must reach the kernel within the 250 ms watchdog, or the kernel would take it
    /// for a hang and disable the plugin instead of retrying it.
    @Test
    func aRealCrashIsSeenWithinTheWatchdog() async throws {
        let (executor, events) = executor()
        executor.start(trap, entryPoint: "ProbeTrap")
        #expect(try await events.wait(for: .available, count: 1))

        let started = ContinuousClock.now
        let outcome = await dispatch(.refresh, to: trap, on: executor).outcome
        let elapsed = ContinuousClock.now - started

        #expect(outcome == .failed)
        #expect(elapsed < .milliseconds(250), "The crash took \(elapsed) to reach the kernel")
    }
}
