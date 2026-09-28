//
//  ResourceReservation.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public struct ResourceReservation: Sendable {
    public let id: UUID
    public let owner: AddonID
}
