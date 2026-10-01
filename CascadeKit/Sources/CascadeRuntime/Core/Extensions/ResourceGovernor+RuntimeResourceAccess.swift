//
//  ResourceGovernor+RuntimeResourceAccess.swift
//  CascadeKit
//

extension ResourceGovernor: RuntimeResourceAccess {

    nonisolated var resourceGovernorTarget: ResourceGovernor { self }
}
