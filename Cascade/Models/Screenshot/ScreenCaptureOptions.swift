//
//  ScreenCaptureOptions.swift
//  Cascade
//

import Foundation

/// ScreenshotTarget keeps the selection independent of the action: the same
/// subject will eventually serve both Capture and Record.
nonisolated enum ScreenshotTarget: String, CaseIterable, Codable, Sendable {

    case screen
    case region
    case window

    var symbol: String {
        switch self {
            case .screen: "menubar.dock.rectangle"
            case .region: "rectangle.dashed"
            case .window: "macwindow"
        }
    }

    var title: String {
        switch self {
            case .screen: String(localized: "Entire Screen")
            case .region: String(localized: "Selected Portion")
            case .window: String(localized: "Single Window")
        }
    }
}

/// ScreenCaptureOptions is an immutable snapshot at the capture boundary.
/// Keeping it small lets the page remember preferences without retaining any
/// display, window, capture stream or image while the notch is closed.
nonisolated struct ScreenCaptureOptions: Codable, Equatable, Sendable {

    var target             : ScreenshotTarget = .screen
    var delaySeconds       : Int = 0
    var directoryPath      : String?
    var includesPointer    = false
    var includesWindowShadow = true
    var includesSystemAudio  = false
    var includesMicrophone   = false
    var showsMouseClicks     = false

    var directoryName: String {
        guard let directoryPath else { return String(localized: "Desktop") }

        return URL(fileURLWithPath: directoryPath).lastPathComponent
    }

    mutating func cycleDelay() {
        switch delaySeconds {
            case ..<3: delaySeconds = 3
            case ..<5: delaySeconds = 5
            case ..<10: delaySeconds = 10
            default: delaySeconds = 0
        }
    }

    mutating func adjustDelay(by seconds: Int) {
        delaySeconds = min(60, max(0, delaySeconds + seconds))
    }
}
