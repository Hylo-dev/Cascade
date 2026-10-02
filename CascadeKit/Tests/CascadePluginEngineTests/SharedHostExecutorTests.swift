//
//  SharedHostExecutorTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct SharedHostExecutorTests {

    private let clock = PluginEngineFixtures.clockID
    private let music = PluginEngineFixtures.musicID

    /// Rig is one executor with its fake transport, clock, and the events and results it reported.
    private struct Rig {

        let executor : SharedHostExecutor
        let transport: FakeHostTransport
        let time     : HostTime
        let events   : Recorder<PluginExecutorEvent>
        let results  : Recorder<PluginExecutionResult.Outcome>

        /// restarts are the delays the executor scheduled to connect again, without the handshake
        /// timeouts every connection schedules.
        var restarts: [Duration] {
            time.delays.filter { $0 != SharedHostExecutor.handshakeTimeout }
        }

        func dispatch(
            _ event  : PluginEvent,
            to plugin: PluginID
        ) {
            executor.dispatch(event, to: plugin) { [results] result in
                results.record(result.outcome)
            }
        }
    }

    private func rig(losesOnStart: Bool = false) -> Rig {
        let transport = FakeHostTransport(losesOnStart: losesOnStart)
        let time      = HostTime()
        let events    = Recorder<PluginExecutorEvent>()
        let executor  = SharedHostExecutor(
            transport: transport,
            clock    : { time.now },
            schedule : { time.schedule($0, $1) }
        )
        executor.observe { events.record($0) }

        return Rig(executor: executor, transport: transport, time: time, events: events, results: Recorder())
    }

    @Test
    func isUnavailableUntilTheHandshakeThenLoadsEveryPlugin() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)

        #expect(link.starts.isEmpty)

        link.greet()

        #expect(link.starts == [clock])
        #expect(rig.events.values == [.unavailable, .available])
    }

    @Test
    func aDispatchWhileUnavailableIsLostAtOnce() {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")

        rig.dispatch(.refresh, to: clock)

        #expect(rig.results.values == [.lost])
        #expect(rig.transport.links.first?.handled.isEmpty == true)
    }

    @Test
    func aCrashFailsTheDispatchInFlightAndComesBackAfterTheFloor() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let first = try #require(rig.transport.links.first)
        first.greet()
        rig.dispatch(.refresh, to: clock)
        rig.time.set(2)

        first.die()

        #expect(rig.results.values == [.failed])
        #expect(rig.events.values == [.unavailable, .available, .unavailable])
        #expect(rig.restarts == [.seconds(8)])

        rig.time.set(10)
        rig.time.runDelayed()
        let second = try #require(rig.transport.links.last)
        second.greet()

        #expect(rig.transport.links.count == 2)
        #expect(second.starts == [clock])
        #expect(rig.events.values.last == .available)
    }

    @Test
    func aCrashAnsweredBeforeTheLossStillCountsAgainstThePlugin() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)
        link.greet()
        rig.dispatch(.refresh, to: clock)
        rig.time.set(100)

        link.answer(0, with: nil)
        link.die()

        #expect(rig.results.values == [.failed])
        #expect(rig.restarts == [.seconds(1)])
    }

    @Test
    func aLossWhileTheHandshakeFinishesLeavesTheHostUnavailable() throws {
        let rig = rig(losesOnStart: true)
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)

        link.greet()
        rig.dispatch(.refresh, to: clock)

        #expect(rig.events.values.last == .unavailable)
        #expect(rig.results.values == [.lost])
    }

    @Test
    func crashesAnsweredBeforeTheLossNeverGiveUpTheHost() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        for index in 0..<3 {
            let link = try #require(rig.transport.links.last)
            rig.time.set(index * 100)
            link.greet()
            rig.dispatch(.refresh, to: clock)
            rig.time.set(index * 100 + 50)
            link.answer(0, with: nil)
            link.die()
            rig.time.runDelayed()
        }

        #expect(rig.transport.links.count == 4)
        #expect(rig.results.values == [.failed, .failed, .failed])
    }

    @Test
    func aKillAnsweredBeforeTheLossIsLost() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)
        link.greet()
        rig.dispatch(.refresh, to: clock)

        rig.executor.stop(clock)
        link.answer(0, with: nil)
        link.die()

        #expect(rig.results.values == [.lost])
    }

    @Test
    func killingForAHangLosesEveryDispatchAndLeavesTheHungPluginOut() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        rig.executor.start(music, entryPoint: "MusicPlugin")
        let first = try #require(rig.transport.links.first)
        first.greet()
        rig.dispatch(.refresh, to: clock)
        rig.dispatch(.refresh, to: music)

        rig.executor.stop(clock)
        first.die()

        #expect(first.wasKilled)
        #expect(rig.results.values == [.lost, .lost])
        #expect(rig.restarts == [.seconds(10)])

        rig.time.runDelayed()
        let second = try #require(rig.transport.links.last)
        second.greet()

        #expect(second.starts == [music])
    }

    @Test
    func stoppingAPluginThatIsNotRunningKillsNothing() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)
        link.greet()

        rig.executor.stop(clock)

        #expect(!link.wasKilled)
    }

    @Test
    func aHostThatKeepsCrashingIdleIsGivenUp() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        for index in 0..<3 {
            let link = try #require(rig.transport.links.last)
            rig.time.set(index * 100)
            link.greet()
            rig.time.set(index * 100 + 50)
            link.die()
            rig.time.runDelayed()
        }

        #expect(rig.transport.links.count == 3)
        #expect(rig.events.values.suffix(2) == [.unavailable, .abandoned])
    }

    @Test
    func anAnswerAfterTheLossIsIgnored() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)
        link.greet()
        rig.dispatch(.refresh, to: clock)
        link.die()

        link.answer(0, with: PluginExecutionResult(output: try PluginOutput(), cpuTime: .zero))

        #expect(rig.results.values == [.failed])
    }

    @Test
    func aHostedSourceStartsInEveryHostAndOnlyTheLiveHostIsHeard() throws {
        let rig      = rig()
        let received = Recorder<PluginSourceEvent>()
        let charging = try PluginEngineFixtures.power(charging: true)
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        rig.executor.startSource("power") { received.record($0) }
        let first = try #require(rig.transport.links.first)

        #expect(first.sourceStarts.isEmpty)

        first.greet()
        first.emit(charging)

        #expect(first.sourceStarts == ["power"])
        #expect(received.values == [charging])

        first.die()
        rig.time.set(10)
        rig.time.runDelayed()
        let second = try #require(rig.transport.links.last)
        second.greet()
        first.emit(try PluginEngineFixtures.power(charging: false))

        #expect(second.sourceStarts == ["power"])
        #expect(received.values == [charging])
    }

    @Test
    func aStoppedSourceStopsInTheHostAndIsNoLongerHeard() throws {
        let rig      = rig()
        let received = Recorder<PluginSourceEvent>()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        rig.executor.startSource("power") { received.record($0) }
        let link = try #require(rig.transport.links.first)
        link.greet()

        rig.executor.stopSource("power")
        link.emit(try PluginEngineFixtures.power(charging: true))

        #expect(link.sourceStops == ["power"])
        #expect(received.values.isEmpty)
    }

    @Test
    func aHostGivenUpOnIsReportedAndARestartConnectsAgain() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        for index in 0..<3 {
            let link = try #require(rig.transport.links.last)
            rig.time.set(index * 20)
            link.greet()
            link.die()
            rig.time.runDelayed()
        }

        #expect(rig.events.values.last == .abandoned)

        let links = rig.transport.links.count
        rig.executor.restart()

        #expect(rig.transport.links.count == links + 1)
    }

    @Test
    func aHandshakeThatNeverCompletesIsALossAndAStaleTimeoutTouchesNothing() throws {
        let rig = rig()
        rig.executor.start(clock, entryPoint: "ClockPlugin")

        #expect(rig.time.delays == [SharedHostExecutor.handshakeTimeout])

        rig.time.set(30)
        rig.time.runDelayed()

        #expect(rig.events.values == [.unavailable, .unavailable])
        #expect(rig.time.delays.count == 1)

        rig.time.set(31)
        rig.time.runDelayed()
        let second = try #require(rig.transport.links.last)
        second.greet()
        rig.time.runDelayed()

        #expect(rig.transport.links.count == 2)
        #expect(rig.events.values.last == .available)
        #expect(second.starts == [clock])
    }

    @Test
    func aHostPastItsMemoryLimitIsRestartedWithoutBlame() throws {
        let rig    = rig()
        let output = try PluginOutput()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        let link = try #require(rig.transport.links.first)
        link.greet()
        rig.dispatch(.refresh, to: clock)
        rig.dispatch(.wake, to: clock)

        link.memoryFootprint = SharedHostExecutor.memoryLimit + 1
        link.answer(0, with: PluginEngineFixtures.result(output))
        link.die()

        #expect(link.wasKilled)
        #expect(rig.results.values == [.output(output), .lost])
    }

    @Test
    func aHostPastItsMemoryLimitOnEveryLaunchIsGivenUp() throws {
        let rig    = rig()
        let output = try PluginOutput()
        rig.executor.start(clock, entryPoint: "ClockPlugin")
        for index in 0..<3 {
            let link = try #require(rig.transport.links.last)
            rig.time.set(index * 20)
            link.greet()
            link.memoryFootprint = SharedHostExecutor.memoryLimit + 1
            rig.dispatch(.refresh, to: clock)
            link.answer(0, with: PluginEngineFixtures.result(output))
            link.die()
            rig.time.runDelayed()
        }

        #expect(rig.transport.links.count == 3)
        #expect(rig.events.values.last == .abandoned)
    }
}
