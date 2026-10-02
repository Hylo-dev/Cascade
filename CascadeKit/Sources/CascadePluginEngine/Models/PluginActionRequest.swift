//
//  PluginActionRequest.swift
//  CascadeKit
//

import CascadeContracts

/// PluginActionRequest is a tap, a toggle or a released slider as the renderer reports it: the
/// publication and revision it was showing, the node it touched and the new value. It names no
/// action. The kernel reads the action from that node in that revision, so a stale or forged
/// request finds nothing to run.
public struct PluginActionRequest: Equatable, Sendable {

    public let key     : PluginPublicationKey
    public let node    : PluginNodeID
    public let revision: UInt64
    public let value   : PluginValue?

    public init(
        key     : PluginPublicationKey,
        node    : PluginNodeID,
        revision: UInt64,
        value   : PluginValue? = nil
    ) {
        self.key      = key
        self.node     = node
        self.revision = revision
        self.value    = value
    }
}
