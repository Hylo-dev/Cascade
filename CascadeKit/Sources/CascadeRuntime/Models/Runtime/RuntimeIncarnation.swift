//
//  RuntimeIncarnation.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeIncarnation is an opaque physical-process identity minted by the host.
struct RuntimeIncarnation: Hashable, Sendable {
    fileprivate let token = UUID()
}
