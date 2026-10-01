//
//  CountlessContainer.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

struct CountlessContainer: UnkeyedDecodingContainer {

    var base        : any UnkeyedDecodingContainer
    var codingPath  : [any CodingKey] { base.codingPath }
    var count       : Int? { nil }
    var isAtEnd     : Bool { base.isAtEnd }
    var currentIndex: Int { base.currentIndex }

    mutating func decodeNil() throws -> Bool { try base.decodeNil() }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try base.decode(type) }

    mutating func nestedContainer<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        try base.nestedContainer(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try base.nestedUnkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder { try base.superDecoder() }
}
