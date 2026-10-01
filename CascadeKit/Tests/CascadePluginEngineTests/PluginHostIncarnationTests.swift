//
//  PluginHostIncarnationTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginHostIncarnationTests {

    /// sleeper starts a child process that waits half a minute, standing in for PluginHost.
    private func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments     = ["30"]
        try process.run()
        return process
    }

    @Test
    func killsTheIncarnationItRecorded() throws {
        let process     = try sleeper()
        let incarnation = try #require(PluginHostIncarnation(pid: process.processIdentifier))

        #expect(incarnation.path == "/bin/sleep")
        #expect(incarnation.kill())

        process.waitUntilExit()

        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
    }

    @Test
    func refusesAProcessThatStartedAtAnotherTime() throws {
        let process = try sleeper()
        defer { process.terminate() }
        let live  = try #require(PluginHostIncarnation(pid: process.processIdentifier))
        let stale = PluginHostIncarnation(
            pid              : live.pid,
            startSeconds     : live.startSeconds - 1,
            startMicroseconds: live.startMicroseconds,
            path             : live.path
        )

        #expect(!stale.kill())
        #expect(process.isRunning)
    }

    @Test
    func refusesAnotherExecutable() throws {
        let process = try sleeper()
        defer { process.terminate() }
        let live    = try #require(PluginHostIncarnation(pid: process.processIdentifier))
        let foreign = PluginHostIncarnation(
            pid              : live.pid,
            startSeconds     : live.startSeconds,
            startMicroseconds: live.startMicroseconds,
            path             : "/usr/bin/false"
        )

        #expect(!foreign.kill())
        #expect(process.isRunning)
    }

    @Test
    func neverKillsThisProcess() throws {
        let own = try #require(PluginHostIncarnation(pid: getpid()))

        #expect(own.isLive)
        #expect(!own.isKillable)
    }

    @Test
    func refusesAProcessThatIsGone() throws {
        let process     = try sleeper()
        let incarnation = try #require(PluginHostIncarnation(pid: process.processIdentifier))
        process.terminate()
        process.waitUntilExit()

        #expect(!incarnation.isLive)
        #expect(!incarnation.kill())
    }
}
