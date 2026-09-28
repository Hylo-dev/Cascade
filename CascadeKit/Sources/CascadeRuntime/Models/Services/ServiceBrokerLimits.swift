//
//  ServiceBrokerLimits.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public struct ServiceBrokerLimits: Sendable {
    public let sessions: Int
    public let permissions: Int
    public let interests: Int
    public let sources: Int
    public let grantsPerOwner: Int
    public let operations: Int
    public let requestsPerOwner: Int
    public let requests: Int
    public init(sessions: Int = 32, permissions: Int = 256, interests: Int = 256,
        sources: Int = 128, grantsPerOwner: Int = 64, operations: Int = 128,
        requestsPerOwner: Int = 128, requests: Int = 1_024) {
        self.sessions = max(0, min(sessions, 32))
        self.permissions = max(0, min(permissions, 256))
        self.interests = max(0, min(interests, 256))
        self.sources = max(0, min(sources, 128))
        self.grantsPerOwner = max(0, min(grantsPerOwner, 64))
        self.operations = max(0, min(operations, 128))
        self.requestsPerOwner = max(0, min(requestsPerOwner, 128))
        self.requests = max(0, min(requests, 1_024))
    }
}
