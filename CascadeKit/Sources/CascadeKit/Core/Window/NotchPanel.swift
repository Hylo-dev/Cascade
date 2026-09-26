//
//  NotchPanel.swift
//  CascadeKit
//

import AppKit
import OSLog

private let fileDropLog = Logger(subsystem: "hylo.Cascade", category: "FileDrop")

/// NotchPanel is the always-on overlay window.
///
/// It is a borderless, nonactivating `NSPanel` so it never steals focus from
/// the app the user is actually working in. Its collection behavior is what
/// makes it persist across every Space and survive full-screen transitions, and
/// its window level sits above the menu bar so the chrome can sit flush in the
/// notch region. The panel never becomes key or main.
///
/// The controller toggles `ignoresMouseEvents` from the exact animated path
/// under the cursor. This matters because the panel's frame spans the whole menu
/// bar and AppKit cannot pass a click to another process using view hit-testing
/// alone.
final class NotchPanel: NSPanel {

    init(contentView: NSView) {

        super.init(
            contentRect: contentView.bounds,
            styleMask  : [.borderless, .nonactivatingPanel],
            backing    : .buffered,
            defer      : false
        )

        // The content canvas keeps its original coordinates above a transparent
        // bottom gutter. A separate root lets its halo extend outside the canvas
        // while remaining inside the window, without changing hit-test geometry.
        let rootView = NSView(frame: contentView.bounds)
        rootView.wantsLayer = true
        rootView.clipsToBounds = false
        rootView.addSubview(contentView)
        self.contentView            = rootView
        isFloatingPanel             = true
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = false
        level                       = .statusBar
        ignoresMouseEvents          = true
        hidesOnDeactivate           = false
        isMovableByWindowBackground = false
        collectionBehavior          = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // A borderless panel refuses key/main by default; we state it explicitly so
    // no future change can accidentally let the overlay grab focus.
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// A public-AppKit drag transport kept in the active user Space. The visual
/// panel is pinned into a private SkyLight space and cannot participate in a
/// Finder destination session, so this transparent panel forwards only native
/// drag callbacks to the visual host's admission logic.
final class NotchFileDropReceiverPanel: NSPanel, NSDraggingDestination {

    private weak var fileDropDestination: NotchHostView?
    private var loggedFileDragWindowSequence: Int?
    private(set) var fileDropDestinationTypeCount = 0

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = NSView(frame: .zero)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    func setFileDropDestination(_ destination: NotchHostView?, enabled: Bool) {
        fileDropDestination = enabled ? destination : nil
        if enabled, destination != nil {
            registerForDraggedTypes(NotchHostView.fileDropTypes)
            fileDropDestinationTypeCount = NotchHostView.fileDropTypes.count
        } else {
            unregisterDraggedTypes()
            fileDropDestinationTypeCount = 0
            loggedFileDragWindowSequence = nil
        }
    }

    func activate(frame: CGRect) {
        if self.frame != frame {
            setFrame(frame, display: false)
        }
        ignoresMouseEvents = false
    }

    func deactivate() {
        ignoresMouseEvents = true
    }

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if loggedFileDragWindowSequence != sender.draggingSequenceNumber {
            loggedFileDragWindowSequence = sender.draggingSequenceNumber
            fileDropLog.notice(
                "phase=windowEntered enabled=\(self.fileDropDestination != nil) registered=\(self.fileDropDestinationTypeCount)"
            )
        }
        return fileDropDestination?.draggingEntered(sender) ?? []
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDropDestination?.draggingUpdated(sender) ?? []
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        fileDropDestination?.draggingExited(sender)
    }

    func draggingEnded(_ sender: any NSDraggingInfo) {
        fileDropDestination?.draggingEnded(sender)
        deactivate()
    }

    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let prepared = fileDropDestination?.prepareForDragOperation(sender) ?? false
        fileDropLog.notice(
            "phase=windowPrepare sequence=\(sender.draggingSequenceNumber) prepared=\(prepared)"
        )
        return prepared
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let accepted = fileDropDestination?.performDragOperation(sender) ?? false
        fileDropLog.notice(
            "phase=windowDrop sequence=\(sender.draggingSequenceNumber) accepted=\(accepted)"
        )
        deactivate()
        return accepted
    }

    func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        fileDropDestination?.concludeDragOperation(sender)
        deactivate()
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
