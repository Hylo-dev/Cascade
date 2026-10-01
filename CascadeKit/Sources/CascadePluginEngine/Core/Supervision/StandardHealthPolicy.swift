//
//  StandardHealthPolicy.swift
//  CascadeKit
//

/// StandardHealthPolicy is the spec's failure table, harvested from `AddonHealthStore`. A throw
/// retries after 1, 5 and then 30 seconds, and the fourth incident inside five minutes, of any
/// kind but a hang, quarantines; the window is closed, so an incident exactly five minutes old
/// still counts. Invalid publications and CPU debt only count: the plugin returned, so there is
/// nothing to retry. A hang disables the plugin, and a second hang since Cascade started
/// quarantines it.
public struct StandardHealthPolicy: PluginHealthPolicy {

    static let window      = Duration.seconds(300)
    static let retryDelays = [Duration.seconds(1), .seconds(5), .seconds(30)]

    public init() {}

    public func reaction(
        to incident: PluginIncident,
        history    : inout PluginHealthHistory,
        at instant : Duration
    ) -> PluginHealthReaction {
        if incident == .hung {
            history.hangs += 1
            return history.hangs > 1 ? .quarantine : .disable
        }

        history.incidents.removeAll { instant - $0 > Self.window }
        history.incidents.append(instant)

        guard history.incidents.count <= Self.retryDelays.count else { return .quarantine }

        return incident == .threw ? .retry(after: Self.retryDelays[history.incidents.count - 1]) : .keep
    }
}
