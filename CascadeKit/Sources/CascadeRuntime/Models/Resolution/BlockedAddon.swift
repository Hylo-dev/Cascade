//
//  BlockedAddon.swift
//  CascadeKit
//

import CascadeContracts

public struct BlockedAddon: Equatable, Sendable {

    public let addonID: AddonID
    public let failure: AddonFailure
}
