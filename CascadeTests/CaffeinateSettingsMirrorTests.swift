//
//  CaffeinateSettingsMirrorTests.swift
//  CascadeTests
//

import CascadeContracts
import Testing
@testable import Cascade

@MainActor
@Suite("Caffeinate settings mirror")
struct CaffeinateSettingsMirrorTests {

    /// Commands records what the mirror sent to the service.
    private final class Commands {

        var sent: [CaffeinateCommand] = []
    }

    private func makeMirror(_ commands: Commands) -> CaffeinateSettingsMirror {
        CaffeinateSettingsMirror(
            glyph            : .cupHeatWaves,
            keepsDisplayAwake: true,
            send             : { commands.sent.append($0) }
        )
    }

    @Test
    func aWriteByTheUserSendsTheMatchingCommand() {
        let commands = Commands()
        let mirror   = makeMirror(commands)

        mirror.glyph             = .mug
        mirror.keepsDisplayAwake = false

        #expect(commands.sent == [.setGlyph(.mug), .setKeepsDisplayAwake(false)])
    }

    @Test
    func writingTheSameValueSendsNothing() {
        let commands = Commands()
        let mirror   = makeMirror(commands)

        mirror.glyph             = .cupHeatWaves
        mirror.keepsDisplayAwake = true

        #expect(commands.sent.isEmpty)
    }

    @Test
    func aPublishedStateUpdatesTheValuesWithoutSendingACommand() {
        let commands = Commands()
        let mirror   = makeMirror(commands)

        mirror.apply(PluginCaffeinateState(keepsDisplayAwake: false, glyph: .pill))

        #expect(mirror.glyph == .pill)
        #expect(!mirror.keepsDisplayAwake)
        #expect(commands.sent.isEmpty)
    }

    @Test
    func aUserWriteAfterAPublishedStateStillSends() {
        let commands = Commands()
        let mirror   = makeMirror(commands)

        mirror.apply(PluginCaffeinateState(keepsDisplayAwake: false))
        mirror.keepsDisplayAwake = true

        #expect(commands.sent == [.setKeepsDisplayAwake(true)])
    }
}
