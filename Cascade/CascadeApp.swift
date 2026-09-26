//
//  CascadeApp.swift
//  Cascade
//
//  Created by Eliomar on 18/06/2026.
//

import AppKit
import SwiftUI
import CascadeKit

@main
struct CascadeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cascade", systemImage: "rectangle.topthird.inset.filled") {
            CascadeMenu(services: appDelegate.services)
                .onAppear { appDelegate.services.refreshNativeReplacement() }
        }
        .menuBarExtraStyle(.menu)

    }
}

/// AppDelegate owns the notch engine for the whole life of the process and
/// starts it once AppKit is ready.
///
/// The engine is the *only* thing the app shell touches: everything else —
/// panel, positioning, morph, widgets — lives behind CascadeKit's public
/// surface, so the shell stays a thin host with no engine internals leaking in.
final class AppDelegate: NSObject, NSApplicationDelegate {

    let services = CascadeServices()

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Run as an accessory (agent) app: no Dock icon, no app menu, and —
        // crucially — the overlay panel is treated as a floating utility rather
        // than a managed application window, so Mission Control and Space
        // switches stop capturing it and dragging it into a desktop thumbnail.
        NSApp.setActivationPolicy(.accessory)

        // Unit tests load the host app too; they must not install system event
        // monitors or trigger a Bluetooth permission request as a side effect.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        services.start()
        if CommandLine.arguments.contains("--open-settings") {
            Task { @MainActor in services.openSettings() }
        }
        if CommandLine.arguments.contains("--calibrate-notch") {
            Task { @MainActor in services.beginSizeCalibration(from: .global) }
        }
        if CommandLine.arguments.contains("--preview-spotlight-droplet") {
            services.previewSpotlightDroplet(from: .global)
        }
        if CommandLine.arguments.contains("--open-spotlight") {
            services.openSpotlight()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
    }
}
