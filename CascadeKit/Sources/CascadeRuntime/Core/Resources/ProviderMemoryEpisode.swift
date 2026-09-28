//
//  ProviderMemoryEpisode.swift
//  CascadeKit
//



/// ProviderMemoryEpisode classifies one physical provider incarnation's current
/// observed footprint without retaining samples, owners, or a clock.
///
/// Missing observations intentionally leave an open episode unchanged: a failed
/// read is not proof that a provider recovered below its target. A replacement
/// physical incarnation receives a new value, so no explicit lifecycle reset can
/// accidentally make an old process look healthy.
struct ProviderMemoryEpisode: Sendable {
    enum Observation: Equatable, Sendable {
        case unavailable
        case withinTarget
        case moderate(isNewEpisode: Bool)
        case severe
    }

    private static let targetBytes: UInt64 = 64 * 1_024 * 1_024
    private static let stopBytes  : UInt64 = 96 * 1_024 * 1_024

    private var isEpisodeOpen = false

    /// observe classifies one current physical footprint.
    ///
    /// The target boundary closes an episode, while the stop boundary remains
    /// moderate so a footprint exactly at that value does not become severe.
    /// A severe sample still opens the episode, preventing a following moderate
    /// sample from being reported as a second entry.
    mutating func observe(footprintBytes: UInt64?) -> Observation {
        guard let footprintBytes else { return .unavailable }
        guard footprintBytes > Self.targetBytes else {
            isEpisodeOpen = false
            return .withinTarget
        }
        guard footprintBytes <= Self.stopBytes else {
            isEpisodeOpen = true
            return .severe
        }
        let isNewEpisode = !isEpisodeOpen
        isEpisodeOpen = true
        return .moderate(isNewEpisode: isNewEpisode)
    }
}
