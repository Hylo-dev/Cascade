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
        Button("Settings…") {
            Task { @MainActor in services.openSettings() }
        }
        .keyboardShortcut(",")

        Divider()

        Toggle("Spotlight from the Notch", isOn: $services.spotlightEnabled)

        Button("Test Liquid Glass Detachment") {
            services.previewSpotlightDroplet(from: .global)
        }

        if services.spotlightEnabled {
            Button("Open Spotlight from the Notch") { services.openSpotlight() }

            Text(services.spotlightStatus)
        }

        Divider()

        Button("Adjust Notch Size…") {
            // Let AppKit finish dismissing the menu before assigning key focus
            // to the calibration panel.
            Task { @MainActor in services.beginSizeCalibration(from: .global) }
        }
        .disabled(!services.canCalibrateDisplay(from: .global))

        Divider()

        Toggle("Haptic Feedback on Hover", isOn: $services.hapticsEnabled)

        Toggle("Show Sensitive Content", isOn: $services.sensitiveContentVisible)

        Toggle("Bluetooth Alerts", isOn: $services.bluetoothEnabled)

        if case .unavailable = services.bluetoothStatus {
            Text("Bluetooth monitoring isn’t available on this system.")
        }

        Toggle("Replace Native Bluetooth Alerts", isOn: $services.nativeReplacementEnabled)
            .disabled(!services.bluetoothEnabled)

        if services.bluetoothEnabled && services.nativeReplacementEnabled {
            switch services.suppressionStatus {
                case .permissionRequired:
                    Button("Allow Accessibility…") { services.requestAccessibility() }
                    Text("Accessibility is required to dismiss native alerts.")

                case .observing:
                    Text("Native alert monitoring is on")
                    Text("The native banner may appear briefly.")

                case .unsupported, .failure:
                    Text("Replacement isn’t available on this system.")
                    Button("Try Again") { services.refreshNativeReplacement() }

                case .stopped:
                    Text("Alert replacement is off")
            }
        }

        Divider()

        Toggle("Volume Alerts in the Notch", isOn: $services.volumeEnabled)

        if services.volumeEnabled {
            switch services.volumeStatus {
                case .active:
                    Text("Volume keys redirected to the notch")

                case .permissionRequired:
                    Button("Allow Accessibility for Volume Keys…") {
                        services.requestVolumeAccessibility()
                    }
                    Text("Without permission, the macOS indicator stays on.")
                    Button("Check Volume Permission Again") { services.refreshVolumePermissions() }

                case .unsupportedOutput:
                    Text("This audio output handles volume through macOS.")

                case .unavailable:
                    Text("macOS volume indicator is on")
                    Button("Retry Volume Replacement") { services.refreshVolumePermissions() }

                case .starting:
                    Text("Turning on volume alerts…")
                case .stopped:
                    Text("Volume alerts are off")
            }
        }

        Button("Test Volume Alert") { services.previewVolume() }
            .disabled(!services.volumeEnabled)

        Divider()

        Toggle("Charging Alerts in the Notch", isOn: $services.chargingEnabled)

        Menu("Test Charging Alert") {

            Button("Normal · Green") { services.previewCharging(lowPower: false) }

            Button("Low Power Mode · Yellow") { services.previewCharging(lowPower: true) }
        }
        .disabled(!services.chargingEnabled)

        Divider()

        Toggle("Music Live Activity", isOn: $services.musicEnabled)

        if services.musicEnabled {
            switch services.musicStatus {
                case .permissionRequired(let message):
                    Text(message)
                    Button("Allow Access to Music and Spotify…") { services.requestMusicAccess() }

                case .unavailable(let message):
                    Text(message)
                    Button("Retry Player Access…") { services.requestMusicAccess() }

                case .monitoring:
                    Text("Apple Music and Spotify")
                    Button("Authorize Another Open Player…") { services.requestMusicAccess() }

                case .stopped:
                    Text("Music Live Activity is off")
            }

            Toggle("Bars from Playing Audio", isOn: $services.audioVisualizerEnabled)

            if services.audioVisualizerEnabled {
                switch services.audioSpectrumStatus {
                    case .capturing:
                        Text("Audio visualizer is on")

                    case .permissionRequired:
                        Button("Allow System Audio in System Settings…") {
                            services.openAudioCaptureSettings()
                        }
                        Button("Check Audio Permission Again") { services.retryAudioCapture() }

                    case .unavailable:
                        Text("Audio isn’t available to the visualizer")
                        Button("Retry Audio Visualizer") { services.retryAudioCapture() }

                    case .stopped:
                        Text("The bars turn on during playback.")
                }
            }
        }

        Button("Test AirPods Alert") { services.previewBluetooth() }
            .disabled(!services.bluetoothEnabled)

        Divider()

        Button("Quit Cascade") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
