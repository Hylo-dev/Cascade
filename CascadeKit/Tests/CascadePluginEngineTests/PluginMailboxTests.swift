//
//  PluginMailboxTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginMailboxTests {

    private static func action() throws -> PluginMailbox.Action {
        PluginMailbox.Action(
            event   : try PluginActionEvent(feature: "now-playing", action: "next"),
            request : PluginActionRequest(
                key     : PluginPublicationKey(plugin: PluginEngineFixtures.musicID, feature: "now-playing", surface: .activity),
                node    : PluginNodeID(rawValue: "#next:button"),
                revision: 1
            ),
            postedAt: .zero
        )
    }

    @Test
    func keepsOnlyTheLatestStateOfEachSourceInArrivalOrder() throws {
        let two     = try PluginEngineFixtures.nowPlaying("Two")
        let power   = try PluginEngineFixtures.power(charging: true)
        var mailbox = PluginMailbox()

        mailbox.post(.source(try PluginEngineFixtures.nowPlaying("One")))
        mailbox.post(.source(power))
        mailbox.post(.source(two))

        #expect(mailbox.take() == .event(.source(two)))
        #expect(mailbox.take() == .event(.source(power)))
        #expect(mailbox.take() == nil)
    }

    @Test
    func takesActionsThenSourcesThenARefreshThenAWake() throws {
        let action  = try Self.action()
        let power   = try PluginEngineFixtures.power(charging: false)
        var mailbox = PluginMailbox()

        mailbox.post(.wake)
        mailbox.post(.refresh)
        mailbox.post(.source(power))
        let queued = mailbox.queue(action)

        #expect(queued)
        #expect(mailbox.take() == .action(action))
        #expect(mailbox.take() == .event(.source(power)))
        #expect(mailbox.take() == .event(.refresh))
        #expect(mailbox.take() == .event(.wake))
        #expect(mailbox.isEmpty)
    }

    @Test
    func coalescesRefreshesAndWakes() {
        var mailbox = PluginMailbox()

        mailbox.post(.refresh)
        mailbox.post(.refresh)
        mailbox.post(.wake)
        mailbox.post(.wake)

        #expect(mailbox.take() == .event(.refresh))
        #expect(mailbox.take() == .event(.wake))
        #expect(mailbox.take() == nil)
    }

    @Test
    func refusesAnActionPastEight() throws {
        let action  = try Self.action()
        var mailbox = PluginMailbox()

        for _ in 1...8 {
            let accepted = mailbox.queue(action)
            #expect(accepted)
        }

        let refused = mailbox.queue(action)

        #expect(!refused)
    }

    @Test
    func anActionPostedWithoutItsRequestIsIgnored() throws {
        var mailbox = PluginMailbox()

        mailbox.post(.action(try Self.action().event))

        #expect(mailbox.isEmpty)
    }

    @Test
    func removeAllEmptiesIt() {
        var mailbox = PluginMailbox()
        mailbox.post(.refresh)

        mailbox.removeAll()

        #expect(mailbox.isEmpty)
    }
}
