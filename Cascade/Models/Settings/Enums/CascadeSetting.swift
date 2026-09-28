//
//  CascadeSetting.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// CascadeSetting shares display metadata with search, so every search result
/// leads to a real control backed by the same services as the menu bar.
enum CascadeSetting: String, CaseIterable, Identifiable {
    case size, haptics, privacy, displayStyle, activityDisplays
    case volumePreview, chargingPreview, lowPowerPreview, bluetoothPreview, spotlightPreview
    case music, visualizer, bluetooth, nativeBluetooth, volume, charging, spotlight

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
        case .size: "Dimensioni del notch hardware"
        case .haptics: "Feedback aptico"
        case .privacy: "Mostra contenuti sensibili"
        case .displayStyle: "Stile sugli schermi"
        case .activityDisplays: "Mostra Live Activities"
        case .volumePreview: "Avviso volume"
        case .chargingPreview: "Avviso ricarica"
        case .lowPowerPreview: "Risparmio energetico"
        case .bluetoothPreview: "Avviso AirPods"
        case .spotlightPreview: "Distacco Spotlight"
        case .music: "Musica"
        case .visualizer: "Visualizzatore audio"
        case .bluetooth: "Bluetooth"
        case .nativeBluetooth: "Sostituisci avvisi di macOS"
        case .volume: "Volume"
        case .charging: "Ricarica"
        case .spotlight: "Spotlight"
        }
    }

    var subtitle: String {
        switch self {
        case .size: "Allinea il notch alla fotocamera del tuo Mac."
        case .haptics: "Un tocco del trackpad quando il notch si espande."
        case .privacy: "Rendi visibili anche le attività private."
        case .displayStyle: "Scegli Notch o Dynamic Island per ogni display senza taglio."
        case .activityDisplays: "Scegli su quali schermi mostrare le attività."
        case .volumePreview: "Mostra un’anteprima senza cambiare il volume."
        case .chargingPreview: "Anteprima della batteria in carica."
        case .lowPowerPreview: "Anteprima della ricarica in modalità risparmio."
        case .bluetoothPreview: "Simula la connessione degli auricolari."
        case .spotlightPreview: "Prova l’animazione Liquid Glass."
        case .music: "Riproduzione e controlli di Apple Music e Spotify."
        case .visualizer: "Anima le barre con l’audio in riproduzione."
        case .bluetooth: "Mostra connessione e batteria degli accessori."
        case .nativeBluetooth: "Usa il notch per gli avvisi Bluetooth."
        case .volume: "Mostra il livello quando premi i tasti volume."
        case .charging: "Mostra un avviso quando colleghi l’alimentazione."
        case .spotlight: "Apri la ricerca di sistema dal notch."
        }
    }

    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let searchable = "\(page.title) \(title) \(subtitle) \(searchKeywords)"
        return terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
    }

    private var searchKeywords: String {
        switch self {
        case .displayStyle: "schermo display notch Dynamic Island style"
        case .activityDisplays: "attività schermo display activity"
        default: ""
        }
    }
}
