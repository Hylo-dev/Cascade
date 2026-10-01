//
//  PluginHostClientProtocol.swift
//  CascadeKit
//

import Foundation

/// PluginHostClientProtocol is what the kernel exports to PluginHost on the same connection:
/// the states of the catalog sources it started, as JSON, which the kernel validates as it
/// decodes.
@objc
public protocol PluginHostClientProtocol {

    func sourceChanged(event: Data)
}
