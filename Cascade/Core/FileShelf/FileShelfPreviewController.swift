//
//  FileShelfPreviewController.swift
//  Cascade
//

import AppKit
import CascadeContracts
import CascadeKit
import CascadePresentation
import CascadeRuntime
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Owns the Quick Look window for exactly as long as the host keeps its checked lease open.
@MainActor
final class FileShelfPreviewController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<Void, Never>?

    func present(_ url: URL) async throws {
        close()
        guard let preview = QLPreviewView(
            frame: CGRect(x: 0, y: 0, width: 720, height: 520),
            style: .normal
        ) else {
            throw FileWorkspaceError.ioFailure
        }
        preview.previewItem = url as NSURL
        preview.autostarts = true
        let panel = NSPanel(
            contentRect: preview.frame,
            styleMask : [.titled, .closable, .resizable],
            backing   : .buffered,
            defer     : false
        )
        panel.title = url.lastPathComponent
        panel.contentView = preview
        panel.delegate = self
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        await withCheckedContinuation { continuation = $0 }
    }

    func close() {
        panel?.close()
        finish()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        panel?.delegate = nil
        panel = nil
        continuation?.resume()
        continuation = nil
    }
}
