//
//  RecordingArrangementStore.swift
//  CascadeKit
//

import Synchronization
@testable import CascadeKit

/// RecordingArrangementStore hands back the arrangements a test seeds it with and records every
/// save, so the host's restore and persistence can be checked without UserDefaults.
final class RecordingArrangementStore: WidgetArrangementStoring {

    private let state: Mutex<(seeded: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]], saved: [[DisplayIdentity: [WidgetIdentifier: WidgetPlacement]]])>

    init(seeded: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]] = [:]) {
        state = Mutex((seeded: seeded, saved: []))
    }

    var saved: [[DisplayIdentity: [WidgetIdentifier: WidgetPlacement]]] {
        state.withLock { $0.saved }
    }

    func load() async -> [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]] {
        state.withLock { $0.seeded }
    }

    func save(_ arrangements: [DisplayIdentity: [WidgetIdentifier: WidgetPlacement]]) {
        state.withLock { $0.saved.append(arrangements) }
    }
}
