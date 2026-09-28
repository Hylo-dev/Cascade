//
//  BlockedAddon.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct BlockedAddon: Equatable, Sendable {
    public let addonID: AddonID
    public let failure: AddonFailure
}
