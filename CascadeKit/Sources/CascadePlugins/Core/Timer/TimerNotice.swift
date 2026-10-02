//
//  TimerNotice.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// TimerNotice is what the timer shows when it is done, whether or not its widget is on screen:
/// the timer symbol leading, "Done" trailing, the symbol alone when minimal, in the orange of the
/// system's timer, for four seconds on a neutral rim. VoiceOver reads that the timer finished.
/// It is always the same notice; the kernel shows a notice again even when it equals the last
/// one, so every finish is told.
enum TimerNotice {

    private static let orange = PluginColor(red: 1, green: 0.62, blue: 0.04)

    static func publication() throws -> PluginPublication {
        try PluginPublication(
            feature : TimerPlugin.finished,
            surface : .notice,
            document: PluginDocument(
                root: Regions {

                    symbol

                    Text(String(localized: "Done", table: "Plugins", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    symbol
                }
            ),
            notice  : PluginNoticeAttributes(
                duration          : 4,
                border            : .neutral,
                accessibilityLabel: String(localized: "Timer finished", table: "Plugins", bundle: .module)
            )
        )
    }

    private static var symbol: PluginNode {
        Image(systemName: "timer")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(orange)
    }
}
