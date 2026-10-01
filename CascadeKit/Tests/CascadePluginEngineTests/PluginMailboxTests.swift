//
//  PluginMailboxTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginMailboxTests {

    @Test
    func keepsOnlyTheLatestStateOfEachSourceInArrivalOrder() throws {
        let two     = try PluginEngineFixtures.nowPlaying("Two")
        let power   = try PluginEngineFixtures.power(charging: true)
        var mailbox = PluginMailbox()

        _ = mailbox.post(.source(try PluginEngineFixtures.nowPlaying("One")))
        _ = mailbox.post(.source(power))
        _ = mailbox.post(.source(two))

        #expect(mailbox.take() == .source(two))
        #expect(mailbox.take() == .source(power))
        #expect(mailbox.take() == nil)
    }

    @Test
    func takesActionsThenSourcesThenARefreshThenAWake() throws {
        let action  = try PluginActionEvent(feature: "now-playing", action: "next")
        let power   = try PluginEngineFixtures.power(charging: false)
        var mailbox = PluginMailbox()

        _ = mailbox.post(.wake)
        _ = mailbox.post(.refresh)
        _ = mailbox.post(.source(power))
        _ = mailbox.post(.action(action))

        #expect(mailbox.take() == .action(action))
        #expect(mailbox.take() == .source(power))
        #expect(mailbox.take() == .refresh)
        #expect(mailbox.take() == .wake)
        #expect(mailbox.isEmpty)
    }

    @Test
    func coalescesRefreshesAndWakes() {
        var mailbox = PluginMailbox()

        _ = mailbox.post(.refresh)
        _ = mailbox.post(.refresh)
        _ = mailbox.post(.wake)
        _ = mailbox.post(.wake)

        #expect(mailbox.take() == .refresh)
        #expect(mailbox.take() == .wake)
        #expect(mailbox.take() == nil)
    }

    @Test
    func refusesAnActionPastEight() throws {
        let action  = try PluginActionEvent(feature: "now-playing", action: "next")
        var mailbox = PluginMailbox()

        for _ in 1...8 {
            let accepted = mailbox.post(.action(action))
            #expect(accepted)
        }

        let refused = mailbox.post(.action(action))

        #expect(!refused)
    }

    @Test
    func removeAllEmptiesIt() {
        var mailbox = PluginMailbox()
        _ = mailbox.post(.refresh)

        mailbox.removeAll()

        #expect(mailbox.isEmpty)
    }
}
