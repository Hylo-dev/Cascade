//
//  SubscriptionStrictGrant.swift
//  CascadeKit
//

import Foundation

struct SubscriptionStrictGrant: Decodable {
    let value: Grant
    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        let generation = try fields.superDecoder(forKey: .generation)
        try SubscriptionWireValidation.fields(generation, exactly: ["value"])
        value = try Grant(from: decoder)
        try SubscriptionWireValidation.grant(value)
    }
    private enum Keys: String, CodingKey { case generation }
}
