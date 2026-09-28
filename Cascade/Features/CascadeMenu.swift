//
//  CascadeMenu.swift
//  Cascade
//

import AppKit
import SwiftUI

/// CascadeMenu exposes the integration controls without requiring the overlay
/// to become a key window. Permission state is rechecked on menu presentation.
struct CascadeMenu: View {
    @Bindable
    var services: CascadeServices

    var body: some View {
        Button("Impostazioni…") {
            Task { @MainActor in services.openSettings() }
        }
        .keyboardShortcut(",")
        Divider()
        Toggle("Spotlight dal notch", isOn: $services.spotlightEnabled)
        Button("Prova il distacco Liquid Glass") {
            services.previewSpotlightDroplet(from: .global)
        }
        if services.spotlightEnabled {
            Button("Apri Spotlight dal notch") { services.openSpotlight() }
            Text(services.spotlightStatus)
        }
        Divider()
        Button("Regola dimensioni del notch…") {
            // Let AppKit finish dismissing the menu before assigning key focus
            // to the calibration panel.
            Task { @MainActor in services.beginSizeCalibration(from: .global) }
        }
        .disabled(!services.canCalibrateDisplay(from: .global))
        Divider()
        Toggle("Feedback aptico in hover", isOn: $services.hapticsEnabled)
        Toggle("Mostra contenuti sensibili", isOn: $services.sensitiveContentVisible)
        Toggle("Avvisi Bluetooth", isOn: $services.bluetoothEnabled)
        if case .unavailable = services.bluetoothStatus {
            Text("Monitor Bluetooth non disponibile su questo sistema.")
        }
        Toggle("Sostituisci avvisi Bluetooth nativi", isOn: $services.nativeReplacementEnabled)
            .disabled(!services.bluetoothEnabled)

        if services.bluetoothEnabled && services.nativeReplacementEnabled {
            switch services.suppressionStatus {
            case .permissionRequired:
                Button("Consenti Accessibilità…") { services.requestAccessibility() }
                Text("Accessibilità necessaria per chiudere gli avvisi nativi.")
            case .observing:
                Text("Monitoraggio degli avvisi nativi attivo")
                Text("Il banner nativo può comparire brevemente.")
            case .unsupported, .failure:
                Text("Sostituzione non disponibile su questo sistema.")
                Button("Riprova") { services.refreshNativeReplacement() }
            case .stopped:
                Text("Sostituzione degli avvisi non attiva")
            }
        }

        Divider()
        Toggle("Avvisi volume nel notch", isOn: $services.volumeEnabled)
        if services.volumeEnabled {
            switch services.volumeStatus {
            case .active:
                Text("Tasti volume reindirizzati al notch")
            case .permissionRequired:
                Button("Consenti Accessibilità per i tasti volume…") {
                    services.requestVolumeAccessibility()
                }
                Text("Senza permesso resta attivo l'indicatore di macOS.")
                Button("Ricontrolla il permesso volume") { services.refreshVolumePermissions() }
            case .unsupportedOutput:
                Text("Questa uscita audio gestisce il volume con macOS.")
            case .unavailable:
                Text("Indicatore volume di macOS attivo")
                Button("Riprova sostituzione volume") { services.refreshVolumePermissions() }
            case .starting:
                Text("Attivazione avvisi volume…")
            case .stopped:
                Text("Avvisi volume non attivi")
            }
        }
        Button("Prova avviso volume") { services.previewVolume() }
        Divider()
        Toggle("Avvisi ricarica nel notch", isOn: $services.chargingEnabled)
        Menu("Prova avviso ricarica") {
            Button("Normale · verde") { services.previewCharging(lowPower: false) }
            Button("Risparmio energetico · giallo") { services.previewCharging(lowPower: true) }
        }
        Divider()
        Toggle("Live Activity musicale", isOn: $services.musicEnabled)
        if services.musicEnabled {
            switch services.musicStatus {
            case .permissionRequired(let message):
                Text(message)
                Button("Consenti accesso a Music e Spotify…") { services.requestMusicAccess() }
            case .unavailable(let message):
                Text(message)
                Button("Riprova accesso al player…") { services.requestMusicAccess() }
            case .monitoring:
                Text("Apple Music e Spotify")
                Button("Autorizza un altro player aperto…") { services.requestMusicAccess() }
            case .stopped:
                Text("Live Activity musicale non attiva")
            }
            Toggle("Barre dall’audio riprodotto", isOn: $services.audioVisualizerEnabled)
            if services.audioVisualizerEnabled {
                switch services.audioSpectrumStatus {
                case .capturing:
                    Text("Visualizzatore audio attivo")
                case .permissionRequired:
                    Button("Consenti audio di sistema nelle Impostazioni…") { services.openAudioCaptureSettings() }
                    Button("Ricontrolla il permesso audio") { services.retryAudioCapture() }
                case .unsupported:
                    Text("Le barre richiedono macOS 14.2 o successivo.")
                case .unavailable:
                    Text("Audio non disponibile per il visualizzatore")
                    Button("Riprova visualizzatore audio") { services.retryAudioCapture() }
                case .stopped:
                    Text("Le barre si attivano durante la riproduzione.")
                }
            }
        }
        Button("Prova avviso AirPods") { services.previewBluetooth() }
        Divider()
        Button("Esci da Cascade") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
