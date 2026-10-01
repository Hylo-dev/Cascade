//
//  Fixture.swift
//  StandaloneClock
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneClockProvider
import Testing

struct Fixture {

    let owner      = AddonID(rawValue: "org.cascade.examples.clock")!
    let assignment: PublicationID
    let now        = Date(timeIntervalSince1970: 2_000_000_000)

    init() {
        assignment = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    func context() throws -> AddonContext {
        try AddonContext(
            services  : FailingServices(),
            storage   : FailingStorage(),
            assets    : FailingAssets(),
            generation: ConnectionGeneration(),
            grants    : []
        )
    }
}
