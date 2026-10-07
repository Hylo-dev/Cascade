//
//  CaffeinateShortcut.swift
//  Cascade
//

import Carbon.HIToolbox

/// CaffeinateShortcut is the global key combination that starts and stops a session: a virtual key
/// code and its modifiers, both in the form Carbon's `RegisterEventHotKey` takes them, so the value
/// reaches the registration untouched and is stored as two integers. A shortcut that is off is not
/// a special value of this type but the absence of one (`nil` in the preferences).
///
/// The key's character comes from a small static table of ANSI letters, digits and function keys
/// instead of the keyboard layout (TIS and `UCKeyTranslate` would cost a lookup and a layout
/// notification for a label). The same table is what the Settings recorder accepts, so every
/// shortcut the user can record has a name; one stored by hand with another key code shows as
/// `Key <code>` and still works.
nonisolated struct CaffeinateShortcut: Codable, Hashable, Sendable {

    /// The default is ⌃⌥⌘C: three modifiers keep it clear of every system and app shortcut that
    /// is only two deep, and C reads as coffee.
    static let `default` = CaffeinateShortcut(
        keyCode  : UInt32(kVK_ANSI_C),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    /// The keys a shortcut may use, with the character each one shows.
    static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_F1) : "F1",  UInt32(kVK_F2) : "F2",  UInt32(kVK_F3) : "F3",
        UInt32(kVK_F4) : "F4",  UInt32(kVK_F5) : "F5",  UInt32(kVK_F6) : "F6",
        UInt32(kVK_F7) : "F7",  UInt32(kVK_F8) : "F8",  UInt32(kVK_F9) : "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]

    /// Carbon's virtual key code, the layout-independent position of the key.
    let keyCode  : UInt32

    /// Carbon modifier flags (`controlKey`, `optionKey`, `shiftKey`, `cmdKey`).
    let modifiers: UInt32

    /// displayString writes the shortcut as macOS does: modifier symbols in the order ⌃⌥⇧⌘, then
    /// the key.
    var displayString: String {
        var text = ""

        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { text += "⌘" }

        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }
}
