//
//  NotchActivityLifetimeTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeKit

struct NotchActivityLifetimeTests {

    @Test
    func boundsSessionsAndDistinguishesStaleContentFromEndedContent() {
        let start    = Date(timeIntervalSince1970: 100)
        let lifetime = NotchActivityLifetime(
            startedAt: start,
            duration : 100_000,
            staleDate: start.addingTimeInterval(60)
        )

        #expect(lifetime.expiresAt == start.addingTimeInterval(8 * 60 * 60))
        #expect(!lifetime.isStale(at: start.addingTimeInterval(59)))
        #expect(lifetime.isStale(at: start.addingTimeInterval(60)))
        #expect(!lifetime.hasEnded(at: start.addingTimeInterval(60)))
        #expect(lifetime.hasEnded(at: lifetime.expiresAt))
    }

    @Test
    func invalidDurationsCannotCreateAnUnboundedActivity() {
        let start = Date(timeIntervalSince1970: 100)

        for duration in [Double.nan, .infinity, -.infinity, -1, 0] {
            let lifetime = NotchActivityLifetime(startedAt: start, duration: duration)
            #expect(lifetime.hasEnded(at: start))
        }
    }
}
