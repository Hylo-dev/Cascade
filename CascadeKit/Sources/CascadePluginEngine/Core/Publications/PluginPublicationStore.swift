//
//  PluginPublicationStore.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginPublicationStore is the source of truth for what is on screen, and it outlives the
/// plugins: one that throws or restarts leaves its last valid content in place. Revisions come
/// from one counter, so a revision names exactly one stored document. A document equal to the
/// stored one changes nothing, not even the revision, because nothing a viewer sees changed.
///
/// Content's age is measured on the wall clock, because content ages while the Mac sleeps and
/// uptime does not; a clock change can make one refresh come early or late, and nothing worse.
struct PluginPublicationStore: Sendable {

    /// Entry is one stored publication.
    struct Entry: Equatable, Sendable {

        let revision   : UInt64
        let document   : PluginDocument
        let table      : PluginNodeTable
        var publishedAt: Date
        let staleAfter : TimeInterval?
    }

    private var entries : [PluginPublicationKey: Entry] = [:]
    private var revision: UInt64 = 0

    subscript(key: PluginPublicationKey) -> Entry? {
        entries[key]
    }

    /// apply stores the document and returns the change, or nil when it equals what is stored.
    /// An equal document still renews the publication's age, so it is no longer stale.
    mutating func apply(
        _ document: PluginDocument,
        staleAfter: TimeInterval?,
        for key   : PluginPublicationKey,
        at instant: Date
    ) -> PluginPublicationChange? {
        let previous = entries[key]
        if let previous, previous.document == document {
            renew(key, at: instant)
            return nil
        }

        let table = PluginNodeTable(document)
        let diff  = PluginNodeDiff(from: previous?.table, to: table)
        revision += 1
        entries[key] = Entry(
            revision   : revision,
            document   : document,
            table      : table,
            publishedAt: instant,
            staleAfter : staleAfter
        )

        return PluginPublicationChange(
            key     : key,
            revision: revision,
            content : PluginPublicationChange.Content(document: document, table: table, diff: diff)
        )
    }

    /// renew restarts the content's age. The kernel renews when it asks for a refresh, so a
    /// plugin that answers with nothing new is not asked again before its interval passes.
    mutating func renew(
        _ key     : PluginPublicationKey,
        at instant: Date
    ) {
        entries[key]?.publishedAt = instant
    }

    /// withdraw removes the publication and returns the change, or nil when there was none.
    mutating func withdraw(_ key: PluginPublicationKey) -> PluginPublicationChange? {
        guard entries.removeValue(forKey: key) != nil else { return nil }

        revision += 1
        return PluginPublicationChange(key: key, revision: revision, content: nil)
    }

    /// isStale is true when the stored content outlived its interval. Content with no interval
    /// never goes stale, and a surface with nothing stored is not stale either: its plugin was
    /// asked at start and chose not to publish there.
    func isStale(
        _ key     : PluginPublicationKey,
        at instant: Date
    ) -> Bool {
        guard let entry = entries[key], let staleAfter = entry.staleAfter else { return false }

        return instant.timeIntervalSince(entry.publishedAt) > staleAfter
    }

    /// keys lists a plugin's publications by feature, then surface.
    func keys(of plugin: PluginID) -> [PluginPublicationKey] {
        entries.keys
            .filter { $0.plugin == plugin }
            .sorted { ($0.feature, $0.surface.rawValue) < ($1.feature, $1.surface.rawValue) }
    }
}
