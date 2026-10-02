//
//  PluginNetworkState.swift
//  CascadeKit
//

/// PluginNetworkState is the `network` catalog source's state, typed: whether the Mac can reach
/// the network, through which kind of link, and whether the system calls that link expensive,
/// as a hotspot is, or constrained, as Low Data Mode makes it. PluginHost's network source
/// builds its events from it and a plugin reads them back with it, so both sides agree on the
/// fields by construction. It reads no network name and says nothing about a connection's
/// speed, so it needs no permission and changes only when the path does.
public struct PluginNetworkState: Equatable, Sendable {

    public static let source = "network"

    public let isConnected  : Bool
    public let interface    : PluginNetworkInterface
    public let isExpensive  : Bool
    public let isConstrained: Bool

    public init(
        isConnected  : Bool,
        interface    : PluginNetworkInterface,
        isExpensive  : Bool,
        isConstrained: Bool
    ) {
        self.isConnected   = isConnected
        self.interface     = interface
        self.isExpensive   = isExpensive
        self.isConstrained = isConstrained
    }

    /// init(_:) reads a network event, or fails for another source's event or a malformed one,
    /// an interface this contract does not name included.
    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .bool(let isConnected)?   = event.fields["isConnected"],
              case .string(let interface)?   = event.fields["interface"],
              let networkInterface           = PluginNetworkInterface(rawValue: interface),
              case .bool(let isExpensive)?   = event.fields["isExpensive"],
              case .bool(let isConstrained)? = event.fields["isConstrained"]
        else { return nil }

        self.init(
            isConnected  : isConnected,
            interface    : networkInterface,
            isExpensive  : isExpensive,
            isConstrained: isConstrained
        )
    }

    /// event is the state as the source emits it.
    public func event() throws -> PluginSourceEvent {
        try PluginSourceEvent(
            source: Self.source,
            fields: [
                "isConnected"  : .bool(isConnected),
                "interface"    : .string(interface.rawValue),
                "isExpensive"  : .bool(isExpensive),
                "isConstrained": .bool(isConstrained),
            ]
        )
    }
}
