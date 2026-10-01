//
//  ServicePathAdmission.swift
//  CascadeKit
//

import Foundation

public struct ServicePathAdmission: Sendable {

    public let id       : UUID
    public let providers: [VerifiedAddonIdentity]
}
