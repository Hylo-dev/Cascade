//
//  PluginValue+Accessors.swift
//  CascadeKit
//

import CascadeContracts

extension PluginValue {

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }

        return value
    }

    var number: Double? {
        guard case .number(let value) = self else { return nil }

        return value
    }
}
