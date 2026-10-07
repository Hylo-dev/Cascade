//
//  CaffeinateShortcutTests.swift
//  CascadeTests
//

import AppKit
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
    func onlyItsOwnHotKeyIdentifierIsAnswered() {
        let ours = EventHotKeyID(signature: 0x4361_6653, id: 1)

        #expect(CaffeinateHotKey.isOurs(ours))
        #expect(!CaffeinateHotKey.isOurs(EventHotKeyID(signature: 0x4F74_6872, id: 1)))
        #expect(!CaffeinateHotKey.isOurs(EventHotKeyID(signature: 0x4361_6653, id: 2)))
    }

    /// aRecorderFreedWhileListeningSaysRecordingEnded covers a recorder released without the
    /// view's `onDisappear`: its owner must still hear the end, on main, or the hot key it freed
    /// for recording would stay unregistered.
    @Test
    func aRecorderFreedWhileListeningSaysRecordingEnded() async {
        var changes  = [Bool]()
        var recorder: CaffeinateShortcutRecording? = CaffeinateShortcutRecording()

        recorder?.begin(
            onRecorded     : { _ in },
            onActiveChanged: { changes.append($0) }
        )
        #expect(changes == [true])

        recorder = nil
        #expect(changes == [true])

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(changes == [true, false])
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
    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "CascadeTests.caffeinate.shortcut.\(UUID().uuidString)"
        let defaults  = UserDefaults(suiteName: suiteName)!

        defer {
            defaults.removePersistentDomain(forName: suiteName)

            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/\(suiteName).plist")
            try? FileManager.default.removeItem(at: plist)
        }

        try body(defaults)
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
    func aBareKeyWithoutModifiersFallsBackToTheDefault() throws {
        try withScratchDefaults { defaults in
            let bare = CaffeinateShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: 0)
            defaults.set(try JSONEncoder().encode(bare), forKey: "caffeinate.shortcut")

            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)

            #expect(preferences.shortcut == CaffeinateShortcut.default)
        }
    }

    @Test
    func aStoredShiftOnlyShortcutFallsBackToTheDefault() throws {
        try withScratchDefaults { defaults in
            let shifted = CaffeinateShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(shiftKey))
            defaults.set(try JSONEncoder().encode(shifted), forKey: "caffeinate.shortcut")

            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)

            #expect(preferences.shortcut == CaffeinateShortcut.default)
        }
    }

    @Test
    func shiftAloneIsNotAModifier() {
        func shortcut(_ modifiers: Int) -> CaffeinateShortcut {
            CaffeinateShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(modifiers))
        }

        #expect(!shortcut(0).hasModifier)
        #expect(!shortcut(shiftKey).hasModifier)
        #expect(shortcut(shiftKey | cmdKey).hasModifier)
        #expect(shortcut(controlKey).hasModifier)
        #expect(shortcut(optionKey).hasModifier)
        #expect(shortcut(cmdKey).hasModifier)
    }

    @Test
    func unreadableDataFallsBackToTheDefault() {
        withScratchDefaults { defaults in
            defaults.set(Data([0xFF, 0x00, 0x13]), forKey: "caffeinate.shortcut")

            let preferences = UserDefaultsCaffeinatePreferences(defaults: defaults)

            #expect(preferences.shortcut == CaffeinateShortcut.default)
        }
    }

    // MARK: Recording

    @Test
    func recordingAcceptsAKeyWithAModifier() {
        let result = CaffeinateShortcut.recording(
            keyCode: UInt16(kVK_ANSI_K),
            flags  : [.command, .shift]
        )

        #expect(
            result == .shortcut(
                CaffeinateShortcut(
                    keyCode  : UInt32(kVK_ANSI_K),
                    modifiers: UInt32(cmdKey | shiftKey)
                )
            )
        )
    }

    @Test
    func recordingMapsEveryModifierToItsCarbonFlag() {
        let result = CaffeinateShortcut.recording(
            keyCode: UInt16(kVK_F5),
            flags  : [.control, .option, .shift, .command, .capsLock]
        )

        #expect(
            result == .shortcut(
                CaffeinateShortcut(
                    keyCode  : UInt32(kVK_F5),
                    modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
                )
            )
        )
    }

    @Test
    func recordingRefusesABareKeyAndShiftAlone() {
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_ANSI_A), flags: []) == .ignored)
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_ANSI_A), flags: [.shift]) == .ignored)
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_ANSI_A), flags: [.capsLock]) == .ignored)
    }

    @Test
    func recordingRefusesAKeyOutsideTheTable() {
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_Space), flags: [.command]) == .ignored)
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_LeftArrow), flags: [.control]) == .ignored)
    }

    @Test
    func escapeCancelsWithOrWithoutModifiers() {
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_Escape), flags: []) == .cancel)
        #expect(CaffeinateShortcut.recording(keyCode: UInt16(kVK_Escape), flags: [.command]) == .cancel)
    }
}
