//
//  CompletionExpectation.swift
//  CascadeKit
//

import Foundation

/// CompletionExpectation is supplied by the host, never inferred from provider output.
public enum CompletionExpectation: Equatable, Sendable {

    case action (requestID: UUID)
    case service(requestID: UUID, contractID: String, operation: String)
}
