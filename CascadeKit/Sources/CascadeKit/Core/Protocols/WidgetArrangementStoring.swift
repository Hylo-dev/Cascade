//
//  WidgetArrangementStoring.swift
//  CascadeKit
//

/// WidgetArrangementStoring keeps the arrangements the user edited, one per display, across
/// launches. Neither call does its work on the caller's thread: `load` hands back what was saved
/// once it has read it, and `save` returns at once and writes in the order it was called, so the
/// main thread only ever applies results. It is a protocol so the host can be tested against an
/// in-memory double instead of the user's defaults.
nonisolated protocol WidgetArrangementStoring: Sendable {

    func load() async -> [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]]

    func save(_ arrangements: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]])
}
