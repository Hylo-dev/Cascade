//
//  PublicationID+Timeline.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

extension PublicationID {
    var stableKey: String { addonID.rawValue + ":" + instanceID.uuidString + ":" + sessionID.uuidString }
}
