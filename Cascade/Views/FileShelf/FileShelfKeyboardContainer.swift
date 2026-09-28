//
//  FileShelfKeyboardContainer.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct FileShelfKeyboardContainer: NSViewRepresentable {
    let content: AnyView
    let interaction: @MainActor (FileShelfEntryInteraction) -> Void

    func makeNSView(context: Context) -> FileShelfKeyboardView {
        FileShelfKeyboardView(content: content, interaction: interaction)
    }

    func updateNSView(_ view: FileShelfKeyboardView, context: Context) {
        view.update(content: content, interaction: interaction)
    }
}
