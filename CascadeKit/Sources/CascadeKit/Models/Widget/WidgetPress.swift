//
//  WidgetPress.swift
//  CascadeKit
//

import CoreGraphics

/// WidgetPress follows one press on a widget tile, from touch-down to release. A press that holds
/// still for `holdDuration` starts editing, as on macOS and iOS; one that moves first is a click
/// or a drag inside the widget and never becomes a hold. Once editing, through that hold or
/// because editing was on already, the tile follows the pointer from where it was when editing
/// began, so the same press that started editing moves the widget at once.
nonisolated struct WidgetPress: Equatable, Sendable {

    static let holdDuration = Duration.milliseconds(500)

    /// slop is how far a press may wander, in points, and still count as holding still.
    static let slop = 4.0

    private(set) var translation = CGSize.zero
    private var hasMoved         = false
    private var origin           : CGSize?

    init(isEditing: Bool) {
        origin = isEditing ? .zero : nil
    }

    /// canStartEditing is true while the press has held still and editing has not begun.
    var canStartEditing: Bool {
        origin == nil && !hasMoved
    }

    /// offset is how far the tile follows the pointer, nil until editing began.
    var offset: CGSize? {
        origin.map { CGSize(width: translation.width - $0.width, height: translation.height - $0.height) }
    }

    mutating func move(to translation: CGSize) {
        self.translation = translation
        if origin == nil, (translation.width * translation.width + translation.height * translation.height).squareRoot() > Self.slop {
            hasMoved = true
        }
    }

    /// beginEditing anchors the tile to where the pointer is now.
    mutating func beginEditing() {
        if origin == nil {
            origin = translation
        }
    }
}
