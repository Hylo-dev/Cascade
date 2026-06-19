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

        // Cascade is an overlay, not a windowed app, so it shows no main window.
        // The empty Settings scene satisfies SwiftUI's "an App needs a Scene"
        // requirement without putting anything on screen at launch.
        Settings {
            EmptyView()
        }
    }
}

/// AppDelegate owns the notch engine for the whole life of the process and
/// starts it once AppKit is ready.
///
/// The engine is the *only* thing the app shell touches: everything else —
/// panel, positioning, morph, widgets — lives behind CascadeKit's public
/// surface, so the shell stays a thin host with no engine internals leaking in.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let notch = NotchEngine(configuration: .debug)

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Run as an accessory (agent) app: no Dock icon, no app menu, and —
        // crucially — the overlay panel is treated as a floating utility rather
        // than a managed application window, so Mission Control and Space
        // switches stop capturing it and dragging it into a desktop thumbnail.
        NSApp.setActivationPolicy(.accessory)

        // Register the demo widget, then start. Widgets are added through the
        // engine's public API; the engine never sees their concrete type.
        for _ in 0...10 {
            notch.register(ClockWidget())
        }

        notch.start()
    }
}
