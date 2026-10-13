//
//  AudioHostClientProtocol.swift
//  CascadeKit
//

import Foundation

/// AudioHostClientProtocol is what the mixer exports to AudioHost on the same connection: the
/// current state, as a JSON `AudioHostSnapshot` the mixer validates as it decodes. AudioHost
/// publishes only when something changed, so the connection costs nothing while the apps are
/// quiet.
@objc
public protocol AudioHostClientProtocol {

    func publish(_ snapshot: Data)
}
