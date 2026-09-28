//
//  NotchPopoverPresenter.swift
//  CascadeKit
//

import AppKit

/// NotchPopoverPresenter is the public widget seam. It walks only the anchor's
/// ancestors to find the notch host and owns a handle to its particular session.
/// Dismantling a widget must call dismiss, including while content is loading.
@MainActor
public final class NotchPopoverPresenter {

    private weak var interaction: NotchAuxiliaryInteraction?
    private var sessionID       : UUID?

    public init() {}

    /// isPresented includes pending content loading, making repeated clicks a
    /// reliable toggle instead of starting overlapping asynchronous requests.
    public var isPresented: Bool {
        guard let sessionID else { return false }

        return interaction?.sessionID == sessionID
    }

    /// present uses the controller's preferred content size or its view's
    /// fitting size. A nil content result cancels the pending presentation.
    @discardableResult
    public func present(
        from anchor  : NSView,
        preferredEdge: NSRectEdge = .minY,
        makeContent  : @escaping @MainActor () async -> NSViewController?
    ) -> Bool {
        var ancestor: NSView? = anchor
        while let view = ancestor {
            if let host = view as? NotchHostView {
                if interaction !== host.auxiliaryInteraction { dismiss() }

                let surface = AppKitNotchAuxiliaryPopover(
                    anchor       : anchor,
                    host         : host,
                    preferredEdge: preferredEdge
                )
                guard surface.anchorFrame != nil else { return false }

                interaction = host.auxiliaryInteraction
                sessionID   = host.auxiliaryInteraction.present(
                    using      : surface,
                    makeContent: makeContent
                )
                return isPresented
            }

            ancestor = view.superview
        }

        dismiss()
        return false
    }

    public func dismiss() {
        let previous = interaction
        let session  = sessionID
        interaction  = nil
        sessionID    = nil

        if let session, previous?.sessionID == session { previous?.dismiss() }
    }

    isolated deinit { dismiss() }
}
