//
//  FileShelfKeyboardView.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileShelfKeyboardView: NSView, NotchKeyboardFocusTarget {
    private let hosting: NSHostingView<AnyView>
    private var interaction: @MainActor (FileShelfEntryInteraction) -> Void

    init(content: AnyView, interaction: @escaping @MainActor (FileShelfEntryInteraction) -> Void) {
        hosting = NSHostingView(rootView: content)
        self.interaction = interaction
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func update(
        content: AnyView,
        interaction: @escaping @MainActor (FileShelfEntryInteraction) -> Void
    ) {
        hosting.rootView = content
        self.interaction = interaction
    }

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123, 126: interaction(.moveFocus(offset: -1, extendSelection: extend))
        case 124, 125: interaction(.moveFocus(offset: 1, extendSelection: extend))
        case 51, 117: interaction(.delete)
        case 0 where event.modifierFlags.contains(.command): interaction(.selectAll)
        default: super.keyDown(with: event)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window, window.firstResponder === self, window.isKeyWindow {
            window.resignKey()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
