//
//  ServicePathAdmission.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import OSLog

public struct ServicePathAdmission: Sendable {
    public let id: UUID
    public let providers: [VerifiedAddonIdentity]
}
