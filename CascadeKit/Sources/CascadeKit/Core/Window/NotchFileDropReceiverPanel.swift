//
//  NotchFileDropReceiverPanel.swift
//  CascadeKit
//

import AppKit
import OSLog

private let fileDropLog = Logger(subsystem: "hylo.Cascade", category: "FileDrop")

/// NotchFileDropReceiverPanel is a public-AppKit drag transport kept in the active
/// user Space. The visual panel is pinned into a private SkyLight space and cannot
/// participate in a Finder destination session, so this transparent panel forwards
/// only native drag callbacks to the visual host's admission logic.
final class NotchFileDropReceiverPanel: NSPanel, NSDraggingDestination {

    /// AppKit sends fresh window tags to WindowServer on every assignment, even
    /// an unchanged one, and the controller reapplies interception on each morph
    /// frame. Measured at ~15 % of a hover's main-thread time plus a window
    /// server fence on every commit; writing only real changes removes both.
    override var ignoresMouseEvents: Bool {
        get { super.ignoresMouseEvents }
        set {
            guard newValue != super.ignoresMouseEvents else { return }
            super.ignoresMouseEvents = newValue
        }
    }

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
