//
//  PluginPublicationChange.swift
//  CascadeKit
//

import CascadeContracts

/// PluginPublicationChange is what the renderer receives when a publication changes: its new
/// revision and, unless it was withdrawn, the document, its node table and the diff from the
/// previous revision, so the renderer touches only the nodes in the diff.
public struct PluginPublicationChange: Equatable, Sendable {

    /// Content is a publication that is on screen.
    public struct Content: Equatable, Sendable {

        public let document: PluginDocument
        public let table   : PluginNodeTable
        public let diff    : PluginNodeDiff
    }

    public let key     : PluginPublicationKey
    public let revision: UInt64
    public let content : Content?
}
