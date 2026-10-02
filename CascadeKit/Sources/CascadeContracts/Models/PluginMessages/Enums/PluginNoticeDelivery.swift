//
//  PluginNoticeDelivery.swift
//  CascadeKit
//

/// PluginNoticeDelivery says what a notice publication does on the notch. `show` is a new event,
/// shown again even when it equals the last one. `update` enriches the notice on screen, keeping
/// its place and its deadline, and is dropped when that notice is already gone, so a late detail
/// can never bring a dismissed event back.
public enum PluginNoticeDelivery: String, Codable, Hashable, Sendable {

    case show
    case update
}
