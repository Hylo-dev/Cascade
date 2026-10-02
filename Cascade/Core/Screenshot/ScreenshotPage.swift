//
//  ScreenshotPage.swift
//  Cascade
//

import AppKit
import CascadeKit
import Observation
import SwiftUI

/// ScreenshotPage owns the short-lived screenshot controls. The host keeps
/// this page open until dismissal; no capture resources or timers are acquired
/// merely to show it. Its observable mode changes only on a button press.
@MainActor
@Observable
final class ScreenshotPage: NotchContextualPage {

    let id                 = "cascade.screenshot"
    let contentHeight     : CGFloat = 144
    let contentRevision   : UInt64 = 0
    let accessibilityLabel = String(localized: "Screen Capture")

    private(set) var isPresented = false
    private(set) var mode        = ScreenshotMode.capture
    var errorMessage: String?
    var showsOptions = false
    var options: ScreenCaptureOptions {
        didSet { persistOptions() }
    }

    /// canCapture keeps the layout experiment honest: the current native
    /// pipeline accepts a whole display, so other targets cannot capture the
    /// wrong subject while their desktop selection interaction is unfinished.
    var canCapture: Bool { options.target == .screen }

    @ObservationIgnored
    private let preferences: UserDefaults
    private static let optionsKey = "screenshot.captureOptions"

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if let data = preferences.data(forKey: Self.optionsKey),
           let saved = try? JSONDecoder().decode(ScreenCaptureOptions.self, from: data) {
            options = saved
            options.delaySeconds = min(60, max(0, options.delaySeconds))
        } else {
            options = ScreenCaptureOptions()
        }
    }

    var keepsExpandedPresentation: Bool { isPresented }

    @ObservationIgnored
    var onPresentationChanged: (@MainActor () -> Void)?

    @ObservationIgnored
    var onAction: (@MainActor (ScreenshotMode) -> Void)?

    /// present preserves the current choice when another screenshot shortcut
    /// arrives, rather than replacing content underneath the pointer.
    func present() {
        guard !isPresented else { return }

        errorMessage = nil
        showsOptions = false
        isPresented = true
        onPresentationChanged?()
    }

    func select(_ mode: ScreenshotMode) {
        guard isPresented else { return }

        self.mode = mode
    }

    func perform(_ mode: ScreenshotMode) {
        guard isPresented, canCapture else { return }

        select(mode)
        onAction?(mode)
    }

    func dismiss() {
        guard isPresented else { return }

        isPresented = false
        showsOptions = false
        onPresentationChanged?()
    }

    /// chooseDirectory leaves folder browsing to AppKit. The open panel is
    /// asynchronous; selecting a path never scans or reads that folder here.
    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        if let path = options.directoryPath { panel.directoryURL = URL(fileURLWithPath: path) }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            self?.options.directoryPath = url.path
        }
    }

    private func persistOptions() {
        guard let data = try? JSONEncoder().encode(options) else { return }

        preferences.set(data, forKey: Self.optionsKey)
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        AnyView(ScreenshotView(page: self, context: context))
    }
}
