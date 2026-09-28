//
//  WireKey.swift
//  CascadeKit
//

import Foundation

struct WireKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
