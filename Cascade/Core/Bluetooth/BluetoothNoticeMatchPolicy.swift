//
//  BluetoothNoticeMatchPolicy.swift
//  Cascade
//

import Foundation

/// BluetoothNoticeMatchPolicy rejects ambiguous content rather than guessing from a device name.
nonisolated enum BluetoothNoticeMatchPolicy {
    /// matchingDevice requires an exact name, an OS-sourced connection label and no unrelated content.
    static func matchingDevice(
        in snapshot     : BluetoothNoticeSnapshot,
        hints           : [BluetoothNoticeConnectionHint],
        connectedLabels : Set<String>,
        now             : Date
    ) -> String? {
        let hasSystemBannerIdentity = snapshot.bannerIdentifier == "smart-routing-system-banner"
            && snapshot.dismissButtonIdentifier == "com.apple.controlcenter.dismiss"
        let isSupportedSystemHost = ["com.apple.controlcenter", "com.apple.MenuBarAgent"]
            .contains(snapshot.ownerBundleID)
        let isLegacyWindow = snapshot.ownerBundleID == "com.apple.controlcenter"
            && snapshot.isFloatingWindow
            && snapshot.bannerIdentifier == nil
            && snapshot.dismissButtonIdentifier == nil
        guard (hasSystemBannerIdentity && isSupportedSystemHost) || isLegacyWindow,
              snapshot.isComplete,
              !snapshot.isModal,
              !snapshot.hasInteractiveControls,
              snapshot.closeButtonCount == 1,
              snapshot.width > 0, snapshot.width <= 600,
              snapshot.height > 0, snapshot.height <= 240
        else { return nil }

        let texts = Set(snapshot.texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        guard !texts.isDisjoint(with: connectedLabels) else { return nil }
        for hint in hints where hint.expiresAt > now && !hint.deviceName.isEmpty {
            guard !connectedLabels.contains(hint.deviceName), texts.contains(hint.deviceName) else { continue }
            let isConnectionOnly = texts.allSatisfy { text in
                text == hint.deviceName || connectedLabels.contains(text) || isBatteryPercentage(text)
            }
            if isConnectionOnly { return hint.deviceName }
        }
        return nil
    }

    /// isBatteryPercentage accepts only a bare percentage; arbitrary digits may be a pairing code.
    private static func isBatteryPercentage(_ text: String) -> Bool {
        guard text.hasSuffix("%"), let value = Int(text.dropLast()) else { return false }
        return (0...100).contains(value)
    }
}
