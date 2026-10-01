//
//  PluginPublicationStore.swift
//  CascadeKit
//

import CascadeContracts

/// PluginPublicationStore is the source of truth for what is on screen, and it outlives the
/// plugins: one that throws or restarts leaves its last valid content in place. Revisions come
/// from one counter, so a revision names exactly one stored document. A document equal to the
/// stored one changes nothing, not even the revision, because nothing a viewer sees changed.
struct PluginPublicationStore: Sendable {

    /// Entry is one stored publication.
    struct Entry: Equatable, Sendable {

        let revision   : UInt64
        let document   : PluginDocument
        let table      : PluginNodeTable
        let publishedAt: Duration
        let staleAfter : Duration?
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
        staleAfter: Duration?,
        for key   : PluginPublicationKey,
        at instant: Duration
    ) -> PluginPublicationChange? {
        let previous = entries[key]
        if let previous, previous.document == document {
            entries[key] = Entry(
                revision   : previous.revision,
                document   : previous.document,
                table      : previous.table,
                publishedAt: instant,
                staleAfter : staleAfter
            )
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

    /// withdraw removes the publication and returns the change, or nil when there was none.
    mutating func withdraw(_ key: PluginPublicationKey) -> PluginPublicationChange? {
        guard entries.removeValue(forKey: key) != nil else { return nil }

        revision += 1
        return PluginPublicationChange(key: key, revision: revision, content: nil)
    }

    /// isStale is true when nothing is stored or the stored content outlived its interval.
    func isStale(
        _ key     : PluginPublicationKey,
        at instant: Duration
    ) -> Bool {
        guard let entry = entries[key] else { return true }

        return entry.staleAfter.map { instant - entry.publishedAt > $0 } ?? false
    }

    /// keys lists a plugin's publications by feature, then surface.
    func keys(of plugin: PluginID) -> [PluginPublicationKey] {
        entries.keys
            .filter { $0.plugin == plugin }
            .sorted { ($0.feature, $0.surface.rawValue) < ($1.feature, $1.surface.rawValue) }
    }
}
