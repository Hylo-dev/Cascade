//
//  CascadeSetting.swift
//  Cascade
//

import SwiftUI

/// CascadeSetting shares display metadata with search, so every search result
/// leads to a real control backed by the same services as the menu bar.
enum CascadeSetting: String, CaseIterable, Identifiable {

    case size
    case haptics
    case privacy
    case displayStyle
    case activityDisplays

    case volumePreview
    case chargingPreview
    case lowPowerPreview
    case bluetoothPreview
    case spotlightPreview

    case music
    case visualizer
    case bluetooth
    case nativeBluetooth
    case volume
    case charging
    case spotlight

    var id: Self { self }

    var page: CascadeSettingsPage {
        switch self {
            case .size, .haptics, .privacy, .displayStyle, .activityDisplays: .appearance
            case .volumePreview, .chargingPreview, .lowPowerPreview, .bluetoothPreview, .spotlightPreview: .dev
            default: .widget
        }
    }

    var title: String {
        switch self {
            case .size            : String(localized: "Hardware notch size")
            case .haptics         : String(localized: "Haptic feedback")
            case .privacy         : String(localized: "Show sensitive content")
            case .displayStyle    : String(localized: "Display style")
            case .activityDisplays: String(localized: "Show Live Activities")
            case .volumePreview   : String(localized: "Volume alert")
            case .chargingPreview : String(localized: "Charging alert")
            case .lowPowerPreview : String(localized: "Low Power Mode")
            case .bluetoothPreview: String(localized: "AirPods alert")
            case .spotlightPreview: String(localized: "Spotlight detachment")
            case .music           : String(localized: "Music")
            case .visualizer      : String(localized: "Audio visualizer")
            case .bluetooth       : "Bluetooth"
            case .nativeBluetooth : String(localized: "Replace macOS alerts")
            case .volume          : "Volume"
            case .charging        : String(localized: "Charging")
            case .spotlight       : "Spotlight"
        }
    }

    var subtitle: String {
        switch self {
            case .size            : String(localized: "Align the notch with your Mac’s camera.")
            case .haptics         : String(localized: "A trackpad tap when the notch expands.")
            case .privacy         : String(localized: "Show private activities too.")
            case .displayStyle    : String(localized: "Choose Notch or Dynamic Island for each display without a notch.")
            case .activityDisplays: String(localized: "Choose which displays show activities.")
            case .volumePreview   : String(localized: "Show a preview without changing the volume.")
            case .chargingPreview : String(localized: "Preview the battery while charging.")
            case .lowPowerPreview : String(localized: "Preview charging in Low Power Mode.")
            case .bluetoothPreview: String(localized: "Simulate earbuds connecting.")
            case .spotlightPreview: String(localized: "Try the Liquid Glass animation.")
            case .music           : String(localized: "Playback and controls for Apple Music and Spotify.")
            case .visualizer      : String(localized: "Animate the bars with the audio that’s playing.")
            case .bluetooth       : String(localized: "Show connection and battery for accessories.")
            case .nativeBluetooth : String(localized: "Use the notch for Bluetooth alerts.")
            case .volume          : String(localized: "Show the level when you press the volume keys.")
            case .charging        : String(localized: "Show an alert when you connect power.")
            case .spotlight       : String(localized: "Open system search from the notch.")
        }
    }

    func matches(_ query: String) -> Bool {
        let terms      = query.split(whereSeparator: \.isWhitespace)
        let searchable = "\(page.title) \(title) \(subtitle) \(searchKeywords)"

        return terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
    }

    private var searchKeywords: String {
        switch self {
            case .displayStyle    : String(localized: "screen display notch Dynamic Island style")
            case .activityDisplays: String(localized: "activity screen display")
            default               : ""
        }
    }
}
