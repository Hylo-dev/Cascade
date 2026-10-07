//
//  CaffeinateHotKey.swift
//  Cascade
//

import Carbon.HIToolbox

/// CaffeinateHotKey owns Caffeinate's one global hot key. It uses `RegisterEventHotKey`, which
/// needs no Accessibility or Input Monitoring permission and no event monitor: the system matches
/// the combination itself and wakes Cascade only when it is pressed, so at rest it costs one
/// installed handler and nothing else.
///
/// Carbon delivers the press on the main thread, and the handler does nothing but call `onPress`;
/// the owner decides what a press means (it sends the service a toggle, which is a queue hop).
///
/// The two Carbon references are `nonisolated(unsafe)` on purpose. An `@MainActor` class's `deinit`
/// is nonisolated on the macOS 15 floor (isolated deinit is newer), yet it must release what it
/// registered. The references are only written on the main actor and read again by `deinit`, when
/// no one else holds the object, so nothing can race with them. `register` is the only writer
/// after `init`.
@MainActor
final class CaffeinateHotKey {

    /// One fixed identity: the class never owns more than one hot key at a time. The signature is
    /// the four ASCII bytes of 'CafS', the way Carbon code writes an `OSType`.
    private static let hotKeyIdentifier = EventHotKeyID(
        signature: 0x4361_6653,
        id       : 1
    )

    private let onPress: @MainActor () -> Void

    nonisolated(unsafe) private var handlerReference: EventHandlerRef?
    nonisolated(unsafe) private var hotKeyReference : EventHotKeyRef?

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind : UInt32(kEventHotKeyPressed)
        )

        // The callback is a C function pointer and cannot capture: the object travels as userData,
        // unretained, which is safe because `deinit` removes the handler before the object dies.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }

                let hotKey = Unmanaged<CaffeinateHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.onPress() }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
    }

    deinit {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let handlerReference { RemoveEventHandler(handlerReference) }
    }

    /// register replaces the registered combination with `shortcut`, or leaves none for `nil`.
    /// It answers `false` when the system refuses the new one (another app already owns it): the
    /// previous combination is gone by then, so nothing is registered.
    @discardableResult
    func register(_ shortcut: CaffeinateShortcut?) -> Bool {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        guard let shortcut else { return true }

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            Self.hotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }

        hotKeyReference = reference

        return true
    }
}
