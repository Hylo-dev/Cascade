//
//  CascadeApp.swift
//  Cascade
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
