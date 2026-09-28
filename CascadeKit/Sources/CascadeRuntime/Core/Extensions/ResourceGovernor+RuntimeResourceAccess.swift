//
//  ResourceGovernor+RuntimeResourceAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

extension ResourceGovernor: RuntimeResourceAccess {
    nonisolated var resourceGovernorTarget: ResourceGovernor { self }
}
