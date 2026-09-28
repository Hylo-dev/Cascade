//
//  CascadeContent.swift
//  CascadeKit
//

import CascadeContracts

/// CascadeContent exposes a durable description, never a provider closure or arbitrary view.
public protocol CascadeContent: Sendable {
    var contentNode: ContentNode { get }
}
