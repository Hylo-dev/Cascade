//
//  ProviderMemoryEpisodeTests.swift
//  CascadeKit
//

import Testing
@testable import CascadeRuntime

@Suite
struct ProviderMemoryEpisodeTests {

    private let mebibyte: UInt64 = 1_024 * 1_024

    @Test
    func boundariesClassifyOnePhysicalFootprint() {
        let target = 64 * mebibyte
        let stop   = 96 * mebibyte

        var episode = ProviderMemoryEpisode()
        #expect(episode.observe(footprintBytes: 0) == .withinTarget)
        #expect(episode.observe(footprintBytes: target) == .withinTarget)
        #expect(episode.observe(footprintBytes: target + 1) == .moderate(isNewEpisode: true))

        var atStop = ProviderMemoryEpisode()
        #expect(atStop.observe(footprintBytes: stop) == .moderate(isNewEpisode: true))

        var beyondStop = ProviderMemoryEpisode()
        #expect(beyondStop.observe(footprintBytes: stop + 1) == .severe)

        var maximum = ProviderMemoryEpisode()
        #expect(maximum.observe(footprintBytes: .max) == .severe)
    }

    @Test
    func episodePersistsAcrossUnavailableSamplesAndClosesOnRecovery() {
        let target  = 64 * mebibyte
        let stop    = 96 * mebibyte
        var episode = ProviderMemoryEpisode()

        #expect(episode.observe(footprintBytes: target + 1) == .moderate(isNewEpisode: true))
        #expect(episode.observe(footprintBytes: target + 2) == .moderate(isNewEpisode: false))
        #expect(episode.observe(footprintBytes: nil) == .unavailable)
        #expect(episode.observe(footprintBytes: target + 3) == .moderate(isNewEpisode: false))
        #expect(episode.observe(footprintBytes: stop + 1) == .severe)
        #expect(episode.observe(footprintBytes: .max) == .severe)
        #expect(episode.observe(footprintBytes: target + 4) == .moderate(isNewEpisode: false))
        #expect(episode.observe(footprintBytes: target) == .withinTarget)
        #expect(episode.observe(footprintBytes: target + 1) == .moderate(isNewEpisode: true))
    }

    @Test
    func eachPhysicalIncarnationStartsItsOwnEpisode() {
        let aboveTarget = 64 * mebibyte + 1
        var first       = ProviderMemoryEpisode()
        var second      = ProviderMemoryEpisode()

        #expect(first.observe(footprintBytes: aboveTarget) == .moderate(isNewEpisode: true))
        #expect(first.observe(footprintBytes: aboveTarget) == .moderate(isNewEpisode: false))
        #expect(second.observe(footprintBytes: aboveTarget) == .moderate(isNewEpisode: true))
    }
}
