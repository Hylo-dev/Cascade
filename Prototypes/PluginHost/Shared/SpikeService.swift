//
//  SpikeService.swift
//  PluginHost
//

import Foundation

/// SpikeService is the whole surface of the PluginHost stand-in: an identity probe, a call
/// that never returns, a cooperative exit and the two permission checks of spike S2.
@objc
protocol SpikeService {

    /// hello replies with the service's own PID and the incarnation it drew at launch.
    func hello(reply: @escaping (Int32, String) -> Void)

    /// hang never replies: it parks the connection's queue the way a plugin stuck in a
    /// synchronous handle() would, without spinning the CPU.
    func hang(reply: @escaping () -> Void)

    /// exitCooperatively ends the service with status 0.
    func exitCooperatively()

    /// automation asks TCC whether this process may send Apple Events to the target.
    func automation(
        bundleIdentifier: String,
        ask             : Bool,
        reply           : @escaping (Int32) -> Void
    )

    /// send asks a running application for its name with a real Apple Event.
    func send(
        bundleIdentifier: String,
        reply           : @escaping (Int32, String) -> Void
    )

    /// bluetooth returns CBManager's authorization, creating a central manager first when
    /// request is set, so an undetermined state raises the system prompt.
    func bluetooth(
        request: Bool,
        reply  : @escaping (Int) -> Void
    )
}

/// SpikeIdentity names the fixture's bundles and the team both sides require.
enum SpikeIdentity {

    static let team = "8KZQJ4JUGS"

    static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
