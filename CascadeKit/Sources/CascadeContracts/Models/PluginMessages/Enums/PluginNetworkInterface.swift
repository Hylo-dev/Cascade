//
//  PluginNetworkInterface.swift
//  CascadeKit
//

/// PluginNetworkInterface is the kind of link the Mac reaches the network through, as the
/// system's path names it, never the network itself: no Wi-Fi name, nothing that needs a
/// permission. A path that reaches nothing is `none`; one through a link the system classes as
/// none of Wi-Fi, Ethernet and cellular is `other`.
public enum PluginNetworkInterface: String, Codable, Sendable {

    case wifi
    case ethernet
    case cellular
    case other
    case none
}
