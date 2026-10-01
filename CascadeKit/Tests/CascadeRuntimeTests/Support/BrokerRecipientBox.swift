//
//  BrokerRecipientBox.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

final class BrokerRecipientBox: @unchecked Sendable {

    private let lock   = NSLock()
    private var stored: [VerifiedAddonIdentity] = []

    var value: [VerifiedAddonIdentity] {
        lock.withLock { stored }
    }

    func store(_ recipients: [VerifiedAddonIdentity]) {
        lock.withLock { stored = recipients }
    }
}
