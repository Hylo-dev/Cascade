//
//  CountlessDecoder.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

struct CountlessDecoder: Decoder {
    let base      : any Decoder
    var codingPath: [any CodingKey] { base.codingPath }
    var userInfo  : [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        try base.container(keyedBy: type)
    }
    func singleValueContainer() throws -> any SingleValueDecodingContainer { try base.singleValueContainer() }
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try CountlessContainer(base: base.unkeyedContainer())
    }
}
