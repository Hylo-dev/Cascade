//
//  StorageResultKind.swift
//  CascadeKit
//

import Foundation

/// StorageResultKind distinguishes absence, present bytes, acknowledgement and failure.
public enum StorageResultKind: String, Codable, Sendable {
    case value, missing, acknowledged, failure
}
