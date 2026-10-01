//
//  SubscriptionWireValidation.swift
//  CascadeKit
//

import Foundation

/// SubscriptionWireValidation holds the checks shared only by the new syntax;
/// existing nested DTO decoders are unchanged.
enum SubscriptionWireValidation {

    static func fields(
        _ decoder      : any Decoder,
        exactly allowed: Set<String>
    ) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == allowed,
            "Invalid subscription wire fields"
        )
    }

    static func grant(_ value: Grant) throws {
        try value.validate()
        try value.scope.validate()
        try value.cost.validate()
    }
}
