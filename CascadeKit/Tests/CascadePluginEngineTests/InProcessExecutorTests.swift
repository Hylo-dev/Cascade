//
//  InProcessExecutorTests.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing

@testable import CascadePluginEngine

@Suite
struct InProcessExecutorTests {

    private let plugin = PluginEngineFixtures.clockID

    @Test
    func measuresTheCPUTimeHandleSpends() async {
        let executor = InProcessExecutor(providers: [
            "ClockPlugin": ScriptedProvider { _ in
                let started = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                while clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - started < 20_000_000 {}
                return try PluginOutput()
            },
        ])
        executor.start(plugin, entryPoint: "ClockPlugin")

        let result = await executor.dispatch(.refresh, to: plugin)

        #expect(result.output != nil)
        #expect(result.cpuTime >= .milliseconds(20))
    }

    @Test
    func reportsAThrowAsNoOutput() async {
        let executor = InProcessExecutor(providers: ["ClockPlugin": ScriptedProvider { _ in throw CancellationError() }])
        executor.start(plugin, entryPoint: "ClockPlugin")

        #expect(await executor.dispatch(.refresh, to: plugin).output == nil)
    }

    @Test
    func reportsAnUnknownEntryPointAsNoOutput() async {
        let executor = InProcessExecutor(providers: [:])
        executor.start(plugin, entryPoint: "ClockPlugin")

        #expect(await executor.dispatch(.refresh, to: plugin).output == nil)
    }

    @Test
    func skipsWhatWasQueuedBehindAStoppedPlugin() async throws {
        let gate     = DispatchSemaphore(value: 0)
        let log      = EventLog()
        let executor = InProcessExecutor(providers: [
            "ClockPlugin": ScriptedProvider { event in
                log.append(event)
                if event == .refresh {
                    _ = gate.wait(timeout: .now() + 5)
                }
                return try PluginOutput()
            },
        ])
        executor.start(plugin, entryPoint: "ClockPlugin")
        executor.dispatch(.refresh, to: plugin) { _ in }
        executor.dispatch(.wake, to: plugin) { _ in }
        #expect(try await eventually { log.events == [.refresh] })

        executor.stop(plugin)
        executor.start(plugin, entryPoint: "ClockPlugin")
        let power = try PluginSourceEvent(source: "power")
        async let last = executor.dispatch(.source(power), to: plugin)
        try await Task.sleep(for: .milliseconds(50))

        #expect(log.events == [.refresh])

        gate.signal()
        _ = await last

        #expect(log.events == [.refresh, .source(power)])
    }
}
