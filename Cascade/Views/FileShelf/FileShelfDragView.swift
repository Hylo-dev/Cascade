//
//  FileShelfDragView.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileShelfDragView: NSView, NSDraggingSource, NotchKeyboardFocusTarget {

    private static let dragThreshold: CGFloat = 4

    private let hosting         : NSHostingView<AnyView>
    private var files           : [PreparedFile]
    private var expandsOnScroll : Bool
    private var scrollNavigation: FileShelfScrollNavigation?
    private var activate        : @MainActor () -> Void
    private var interaction     : (@MainActor (FileShelfEntryInteraction) -> Void)?
    private var resolveDragFiles: (@MainActor () -> [PreparedFile])?
    private var navigateByScroll: @MainActor (FileShelfScrollDirection) -> Void
    private var copy            : @Sendable (PreparedFile, URL) async throws -> Void

    private var downLocation: NSPoint?
    private var beganDrag    = false
    private var scrollPolicy = FileShelfScrollGesturePolicy()

    init(
        content          : AnyView,
        files            : [PreparedFile],
        accessibilityName: String,
        expandsOnScroll  : Bool = false,
        scrollNavigation : FileShelfScrollNavigation? = nil,
        activate         : @escaping @MainActor () -> Void,
        interaction      : (@MainActor (FileShelfEntryInteraction) -> Void)? = nil,
        resolveDragFiles : (@MainActor () -> [PreparedFile])? = nil,
        navigateByScroll : @escaping @MainActor (FileShelfScrollDirection) -> Void = { _ in },
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        hosting               = NSHostingView(rootView: content)
        self.files            = files
        self.expandsOnScroll  = expandsOnScroll
        self.scrollNavigation = scrollNavigation
        self.activate         = activate
        self.interaction      = interaction
        self.resolveDragFiles = resolveDragFiles
        self.navigateByScroll = navigateByScroll
        self.copy             = copy
        super.init(frame: .zero)

        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(localPoint) ? self : nil
    }

    func update(
        content          : AnyView,
        files            : [PreparedFile],
        accessibilityName: String,
        expandsOnScroll  : Bool,
        scrollNavigation : FileShelfScrollNavigation?,
        activate         : @escaping @MainActor () -> Void,
        interaction      : (@MainActor (FileShelfEntryInteraction) -> Void)?,
        resolveDragFiles : (@MainActor () -> [PreparedFile])?,
        navigateByScroll : @escaping @MainActor (FileShelfScrollDirection) -> Void,
        copy             : @escaping @Sendable (PreparedFile, URL) async throws -> Void
    ) {
        hosting.rootView      = content
        self.files            = files
        self.expandsOnScroll  = expandsOnScroll
        self.scrollNavigation = scrollNavigation
        self.activate         = activate
        self.interaction      = interaction
        self.resolveDragFiles = resolveDragFiles
        self.navigateByScroll = navigateByScroll
        self.copy             = copy
        setAccessibilityLabel(accessibilityName)
    }

    override func mouseDown(with event: NSEvent) {
        let responder = keyboardContainer ?? self
        window?.makeFirstResponder(responder)
        window?.makeKey()

        downLocation = convert(event.locationInWindow, from: nil)
        beganDrag    = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !beganDrag, let downLocation else { return }

        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - downLocation.x, current.y - downLocation.y) >= Self.dragThreshold else {
            return
        }

        beganDrag         = true
        self.downLocation = nil
        interaction?(.prepareDrag)

        let dragFiles = resolveDragFiles?() ?? files
        guard !dragFiles.isEmpty else { return }

        let items = dragFiles.enumerated().map { index, file -> NSDraggingItem in
            let provider = FileShelfPromiseProvider.make(file: file, copy: copy)
            let item     = NSDraggingItem(pasteboardWriter: provider)
            let offset   = CGFloat(index) * 3
            let frame    = CGRect(
                x     : current.x - 26 + offset,
                y     : current.y - 20 - offset,
                width : min(max(bounds.width, 52), 118),
                height: min(max(bounds.height, 40), 106)
            )
            let icon = UTType(file.typeIdentifier).map { NSWorkspace.shared.icon(for: $0) }
            item.setDraggingFrame(frame, contents: icon)
            return item
        }
        beginDraggingSession(
            with  : items,
            event : event,
            source: self
        )
    }

    override func mouseUp(with event: NSEvent) {
        let releaseLocation = convert(event.locationInWindow, from: nil)
        let shouldActivate  = downLocation != nil && !beganDrag && bounds.contains(releaseLocation)

        downLocation = nil
        beganDrag    = false

        if shouldActivate {
            if let interaction { interaction(.click(modifiers: event.modifierFlags)) }
            else { activate() }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let responder = keyboardContainer ?? self
        window?.makeFirstResponder(responder)
        window?.makeKey()

        let behavior = scrollNavigation ?? (expandsOnScroll ? .open : nil)
        guard let behavior, event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        let direction = scrollPolicy.navigation(
            delta                    : CGSize(
                width : event.scrollingDeltaX,
                height: event.scrollingDeltaY
            ),
            phase                    : event.phase,
            momentumPhase            : event.momentumPhase,
            behavior                 : behavior,
            isAtHorizontalLeadingEdge: isAtHorizontalLeadingEdge
        )
        if let direction {
            if scrollNavigation == nil { activate() }
            else { navigateByScroll(direction) }
        }
    }

    nonisolated static func shouldExpand(for distance: CGSize) -> Bool {
        FileShelfScrollGesturePolicy.exceedsIntentThreshold(distance)
    }

    private var isAtHorizontalLeadingEdge: Bool {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView
        else { return true }

        return scrollView.documentVisibleRect.minX <= documentView.bounds.minX + 1
    }

    private var keyboardContainer: FileShelfKeyboardView? {
        var ancestor = superview
        while let view = ancestor {
            if let container = view as? FileShelfKeyboardView { return container }
            ancestor = view.superview
        }

        return nil
    }

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
            case 123, 126:
                interaction?(.moveFocus(offset: -1, extendSelection: extend))
            case 124, 125:
                interaction?(.moveFocus(offset: 1, extendSelection: extend))
            case 51, 117:
                interaction?(.delete)
            case 0 where event.modifierFlags.contains(.command):
                interaction?(.selectAll)
            case 36, 49:
                activate()
            default:
                super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window, window.firstResponder === self, window.isKeyWindow {
            window.resignKey()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func draggingSession(
        _ session                     : NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
