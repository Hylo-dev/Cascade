//
//  NotchSizeCalibration.swift
//  CascadeKit
//

import CoreGraphics

/// NotchSizeCalibration owns a reversible sizing session. Draft values drive
/// the real notch and guides together; only an explicit save writes preferences.
@MainActor
final class NotchSizeCalibration {

    var onChange: (() -> Void)?
    var onFinish: (() -> Void)?

    var isActive: Bool { draft != nil }

    private let presenter: any NotchCalibrationPresenting
    private let store    : any NotchSizeStoring

    private var draft: (display: ActiveDisplay, size: CGSize)?

    init(
        presenter: any NotchCalibrationPresenting,
        store    : any NotchSizeStoring
    ) {
        self.presenter = presenter
        self.store     = store

        presenter.onStep   = { [weak self] width, height in self?.step(width: width, height: height) }
        presenter.onFinish = { [weak self] save in self?.finish(save: save) }
    }

    /// size reads cached values only, including during the morph's fast path.
    func size(for display: ActiveDisplay) -> CGSize? {
        if let draft, draft.display.displayID == display.displayID { return draft.size }

        return store.size(for: display.displayID).map { bounded($0, on: display) }
    }

    func begin(
        on display: ActiveDisplay,
        size      : CGSize
    ) {
        guard !isActive else { return }

        let size = bounded(size, on: display)
        draft    = (display, size)

        onChange?()
        presenter.show(on: display, size: size)
    }

    func finish(save: Bool) {
        guard let draft else { return }

        self.draft = nil
        if save { store.setSize(draft.size, for: draft.display.displayID) }

        presenter.hide()
        onFinish?()
    }

    /// update hands the guides the very same resolved sides and bottom as the
    /// rendered notch. The reported width still includes its flared bezel
    /// attachments.
    func update(geometry: NotchGeometry) {
        guard isActive else { return }

        presenter.update(geometry: geometry)
    }

    private func step(
        width : CGFloat,
        height: CGFloat
    ) {
        guard let draft, width.isFinite, height.isFinite else { return }

        let size = bounded(
            CGSize(width: draft.size.width + width, height: draft.size.height + height),
            on: draft.display
        )
        guard size != draft.size else { return }

        self.draft = (draft.display, size)

        onChange?()
        presenter.update(size: size)
    }

    private func bounded(
        _ size    : CGSize,
        on display: ActiveDisplay
    ) -> CGSize {
        CGSize(
            width : min(max(80, size.width), min(400, max(80, display.frame.width - 24))),
            height: min(max(16, size.height), 80)
        )
    }

    isolated deinit {
        if draft != nil { presenter.hide() }
    }
}
