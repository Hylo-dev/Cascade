//
//  RuntimeIncarnation.swift
//  CascadeKit
//

import Foundation

/// RuntimeIncarnation is an opaque physical-process identity minted by the host.
struct RuntimeIncarnation: Hashable, Sendable {

    fileprivate let token = UUID()
}
