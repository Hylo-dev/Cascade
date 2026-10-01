//
//  AddonProvider.swift
//  CascadeKit
//

import CascadeContracts

/// AddonProvider handles finite requests in the controlled provider process.
/// This protocol defines no host registration, execution loop or in-process fallback.
public protocol AddonProvider: Sendable {

    func handle(
        _ event: AddonEvent,
        context: AddonContext
    ) async throws -> ProviderOutput
}
