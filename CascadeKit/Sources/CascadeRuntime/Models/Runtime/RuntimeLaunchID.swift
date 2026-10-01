//
//  RuntimeLaunchID.swift
//  CascadeKit
//

import Foundation

/// RuntimeLaunchID identifies one reserved cold launch before its single attachment.
struct RuntimeLaunchID: Hashable, Sendable {

    fileprivate let token = UUID()
}
