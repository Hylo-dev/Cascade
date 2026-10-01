//
//  KeyedStorageClass.swift
//  CascadeKit
//

/// KeyedStorageClass is host-selected; the eventual SDK facade always selects data.
enum KeyedStorageClass: UInt8, CaseIterable, Sendable {

    case data  = 1
    case cache = 2

    var directoryName: String { self == .data ? "data" : "cache" }
    var maximumBytes : Int { (self == .data ? 10 : 20) * 1_024 * 1_024 }
}
