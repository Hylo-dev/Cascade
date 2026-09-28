//
//  NotchAuxiliaryInteraction.swift
//  CascadeKit
//

import AppKit

/// NotchAuxiliaryInteraction owns one pending or visible auxiliary popover.
/// Pointer samples come from the controller; only a cancellable, one-shot exit
/// deadline wakes independently. No menu tracking loop or window search is used.
@MainActor
final class NotchAuxiliaryInteraction: NSObject {

    var isActive: Bool { sessionID != nil }

    /// onDismiss lets the controller re-evaluate its last pointer sample when
    /// the grace expires while the pointer is stationary. State and resources
    /// are cleared before delivery; replacing a session does not emit this event.
    var onDismiss: (() -> Void)?
    /// onActiveChanged lets the display coordinator retain the invocation
    /// anchor for the complete pending-or-visible popover session.
    var onActiveChanged: ((Bool) -> Void)?

    private(set) var sessionID: UUID?

    private let leaveGrace     : Duration
    private let pointerLocation: @MainActor () -> CGPoint
    private var presentation   : (any NotchAuxiliaryPopoverHosting)?
    private var openingTask    : Task<Void, Never>?
    private var exitTask       : Task<Void, Never>?
    private var exitDeadline   : ContinuousClock.Instant?
    private var lastPointer    : CGPoint?

    init(
        leaveGrace     : Duration = .milliseconds(180),
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.leaveGrace      = leaveGrace
        self.pointerLocation = pointerLocation
        super.init()
    }

    /// contains includes the live notch, owned popup and a 16-point connecting
    /// corridor. During exit grace it also keeps the current session alive;
    /// updatePointer must run BEFORE the controller asks whether to stay open.
    func contains(_ screenPoint: CGPoint) -> Bool {
        guard isActive, presentation?.anchorFrame != nil else { return false }
        if containsGeometry(screenPoint) { return true }
        return exitDeadline.map { ContinuousClock.now < $0 } ?? false
    }

    /// updatePointer cancels an exit on re-entry. Repeated outside samples do
    /// not extend the original deadline, and a detached anchor closes at once.
    func updatePointer(at screenPoint: CGPoint) {
        guard isActive else { return }
        lastPointer = screenPoint
        guard presentation?.anchorFrame != nil else {
            dismiss()
            return
        }
        if containsGeometry(screenPoint) {
            exitTask?.cancel()
            exitTask     = nil
            exitDeadline = nil
            return
        }
        guard exitTask == nil else { return }
        let deadline = ContinuousClock.now.advanced(by: leaveGrace)
        let session  = sessionID
        exitDeadline = deadline
        exitTask = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return } // Cancellation is the normal re-entry path.
            guard !Task.isCancelled,
                  let self,
                  self.sessionID == session,
                  self.exitDeadline == deadline else { return }
            self.exitTask     = nil
            self.exitDeadline = nil
            if let point = self.lastPointer, self.containsGeometry(point) { return }
            self.dismiss()
        }
    }

    /// dismiss invalidates asynchronous work before closing AppKit, because a
    /// close notification or content teardown may synchronously call back here.
    func dismiss() {
        endSession(notify: true)
    }

    /// present registers synchronously, before the first suspension in content
    /// loading. The identity check also rejects providers that ignore cancellation.
    @discardableResult
    func present(
        using presentation: any NotchAuxiliaryPopoverHosting,
        makeContent       : @escaping @MainActor () async -> NSViewController?
    ) -> UUID {
        let wasActive = isActive
        endSession(notify: false)
        let session       = UUID()
        sessionID         = session
        self.presentation = presentation
        if !wasActive { onActiveChanged?(true) }
        openingTask = Task { [weak self] in
            let content = await makeContent()
            guard !Task.isCancelled, let self, self.sessionID == session else { return }
            self.openingTask = nil
            guard let content,
                  let presentation = self.presentation,
                  presentation.anchorFrame != nil,
                  self.exitDeadline.map({ ContinuousClock.now < $0 }) ?? true else {
                self.dismiss()
                return
            }
            guard presentation.show(content, delegate: self) else {
                self.dismiss()
                return
            }
            guard self.sessionID == session else { return }
            self.updatePointer(at: self.lastPointer ?? self.pointerLocation())
        }
        updatePointer(at: pointerLocation())
        return session
    }

    private func endSession(notify: Bool) {
        let wasActive = isActive
        let previous  = presentation
        sessionID     = nil
        presentation  = nil
        lastPointer   = nil
        openingTask?.cancel()
        exitTask?.cancel()
        openingTask  = nil
        exitTask     = nil
        exitDeadline = nil
        previous?.close()
        if wasActive && notify {
            onActiveChanged?(false)
            onDismiss?()
        }
    }

    private func containsGeometry(_ point: CGPoint) -> Bool {
        guard let presentation, let anchor = presentation.anchorFrame else { return false }
        if presentation.containsNotch(point) { return true }
        guard let popup = presentation.popoverFrame else { return false }
        if popup.contains(point) { return true }

        // Use the shortest segment between the actual rectangles, so a popup
        // flipped above or beside its anchor gets the same narrow passage. A
        // detached/centered AppKit placement must not bridge half the display.
        let popupEnd = CGPoint(
            x: min(max(anchor.midX, popup.minX), popup.maxX),
            y: min(max(anchor.midY, popup.minY), popup.maxY)
        )
        let anchorEnd = CGPoint(
            x: min(max(popupEnd.x, anchor.minX), anchor.maxX),
            y: min(max(popupEnd.y, anchor.minY), anchor.maxY)
        )
        let deltaX        = popupEnd.x - anchorEnd.x
        let deltaY        = popupEnd.y - anchorEnd.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0, lengthSquared <= 64 * 64 else { return false }
        let projection = min(max(
            ((point.x - anchorEnd.x) * deltaX + (point.y - anchorEnd.y) * deltaY) / lengthSquared,
            0
        ), 1)
        let distanceX = point.x - (anchorEnd.x + projection * deltaX)
        let distanceY = point.y - (anchorEnd.y + projection * deltaY)
        return distanceX * distanceX + distanceY * distanceY <= 8 * 8
    }

    isolated deinit {
        openingTask?.cancel()
        exitTask?.cancel()
        presentation?.close()
    }
}

extension NotchAuxiliaryInteraction: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              popover === presentation?.popover else { return }
        dismiss()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
}
