//
//  CaffeinateShortcutTests.swift
//  CascadeTests
//

import Carbon.HIToolbox
import Foundation
import Testing
@testable import Cascade

@MainActor
@Suite("Caffeinate shortcut")
struct CaffeinateShortcutTests {

    @Test
    func defaultIsControlOptionCommandC() {
        let shortcut = CaffeinateShortcut.default

        #expect(shortcut.keyCode == UInt32(kVK_ANSI_C))
        #expect(shortcut.modifiers == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test
    func displayStringUsesSymbols() {
        #expect(CaffeinateShortcut.default.displayString == "⌃⌥⌘C")

        let shifted = CaffeinateShortcut(
            keyCode  : UInt32(kVK_F5),
            modifiers: UInt32(shiftKey | cmdKey)
        )
        #expect(shifted.displayString == "⇧⌘F5")

        let digit = CaffeinateShortcut(
            keyCode  : UInt32(kVK_ANSI_7),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(digit.displayString == "⌃⌥⇧⌘7")
    }

    @Test
    func displayStringFallsBackForUnknownKeys() {
        let unknown = CaffeinateShortcut(
            keyCode  : UInt32(kVK_Space),
            modifiers: UInt32(cmdKey)
        )

        #expect(unknown.displayString == "⌘Key \(kVK_Space)")
    }

    @Test
    func shortcutRoundTripsThroughCodable() throws {
        let data    = try JSONEncoder().encode(CaffeinateShortcut.default)
        let decoded = try JSONDecoder().decode(CaffeinateShortcut.self, from: data)

        #expect(decoded == CaffeinateShortcut.default)
    }

    @Test
    func registeringNilUnregisters() {
        var presses = 0
        let hotKey  = CaffeinateHotKey(onPress: { presses += 1 })

        #expect(hotKey.register(nil))
        #expect(presses == 0)

        // Register something obscure, then switch it off: nothing stays registered afterwards.
        let obscure = CaffeinateShortcut(
            keyCode  : UInt32(kVK_F19),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(hotKey.register(obscure))
        #expect(hotKey.register(nil))
        #expect(presses == 0)
    }
}

@Suite("Caffeinate shortcut preferences")
struct CaffeinateShortcutPreferencesTests {

    /// withScratchDefaults runs `body` on a throwaway suite. Removing the persistent domain empties
    /// the suite but cfprefsd leaves its plist behind, so the file goes too.
    private func withScratchDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "CascadeTests.caffeinate.shortcut.\(UUID().uuidString)"
        let defaults  = UserDefaults(suiteName: suiteName)!

        body(defaults)

        defaults.removePersistentDomain(forName: suiteName)

        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    @Test
    func neverSetFallsBackToTheDefault() {
        withScratchDefaults { defaults in
            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)

            #expect(preferences.shortcut == CaffeinateShortcut.default)
        }
    }

    @Test
    func aStoredShortcutComesBack() {
        withScratchDefaults { defaults in
            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)
            let custom      = CaffeinateShortcut(
                keyCode  : UInt32(kVK_ANSI_K),
                modifiers: UInt32(optionKey | cmdKey)
            )

            preferences.shortcut = custom

            #expect(UserDefaultsCaffeinatePreferences(defaults: defaults).shortcut == custom)
        }
    }

    @Test
    func offIsRememberedAsOffNotAsTheDefault() {
        withScratchDefaults { defaults in
            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)

            preferences.shortcut = nil

            #expect(UserDefaultsCaffeinatePreferences(defaults: defaults).shortcut == nil)
        }
    }

    @Test
    func unreadableDataFallsBackToTheDefault() {
        withScratchDefaults { defaults in
            defaults.set(Data([0xFF, 0x00, 0x13]), forKey: "caffeinate.shortcut")

            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)

            #expect(preferences.shortcut == CaffeinateShortcut.default)
        }
    }
}
