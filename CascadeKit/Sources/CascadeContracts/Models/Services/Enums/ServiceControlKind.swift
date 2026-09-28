//
//  ServiceControlKind.swift
//  CascadeKit
//

import Foundation

public enum ServiceControlKind: String, Codable, Equatable, Sendable {
    case acquire, subscribe, unsubscribe
}
