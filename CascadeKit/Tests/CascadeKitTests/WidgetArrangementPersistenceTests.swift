//
//  WidgetArrangementPersistenceTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeKit

/// WidgetArrangementPersistenceTests covers what survives a launch: the store writes and reads
/// the edited arrangements by display, a damaged payload reads as nothing, the host saves every
/// edit and restores what was saved without overwriting an edit made in the meantime.
@MainActor
struct WidgetArrangementPersistenceTests {

    private let builtIn = DisplayIdentity(rawValue: "built-in")
    private let tall    = GridSpan(columns: 4, rows: 2)
    private let wide    = GridSpan(columns: 4, rows: 1)

    private func placement(
        _ column: Int,
        _ row   : Int,
        _ span  : GridSpan
    ) -> WidgetPlacement {
        WidgetPlacement(position: GridPosition(column: column, row: row), span: span)
    }

    private func defaults() throws -> UserDefaults {
        let name = "WidgetArrangementPersistenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)

        return defaults
    }

    @Test
    func theStoreReadsBackWhatItSavedByDisplay() async throws {
        let store    = UserDefaultsWidgetArrangementStore(defaults: try defaults())
        let expected = [builtIn: [WidgetIdentifier("clock"): placement(10, 0, wide)]]

        store.save(expected)
        let loaded = await store.load()

        #expect(loaded == expected)
    }

    @Test
    func aDamagedPayloadReadsAsNothing() async throws {
        let defaults = try defaults()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsWidgetArrangementStore.defaultsKey)
        let store = UserDefaultsWidgetArrangementStore(defaults: defaults)

        let loaded = await store.load()

        #expect(loaded.isEmpty)
    }

    @Test
    func everyEditIsSaved() {
        let store = RecordingArrangementStore()
        let host  = WidgetHost(store: store)
        let clock = EditableWidgetFixture("clock", sizes: [tall])
        host.register(clock)
        host.update(state: .open, display: builtIn)

        host.remove(clock.id)

        #expect(store.saved == [[builtIn: [:]]])
    }

    @Test
    func aSavedArrangementIsRestoredWithoutOverwritingANewerEdit() async {
        let external = DisplayIdentity(rawValue: "external")
        let store    = RecordingArrangementStore(seeded: [
            builtIn : [WidgetIdentifier("clock"): placement(10, 0, wide)],
            external: [WidgetIdentifier("clock"): placement(0, 2, wide)],
        ])
        let host  = WidgetHost(store: store)
        let clock = EditableWidgetFixture("clock", sizes: [tall, wide])
        host.register(clock)
        host.update(state: .open, display: external)
        host.remove(clock.id)
        var changes           = 0
        host.onContentChanged = { changes += 1 }

        await host.restoreArrangements()

        #expect(host.arrangement.isEmpty)
        #expect(changes == 1)

        host.update(state: .closed)
        host.update(state: .open, display: builtIn)
        #expect(host.arrangement == [clock.id: placement(10, 0, wide)])
    }
}
