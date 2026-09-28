//
//  FileShelfEntryInteraction.swift
//  Cascade
//

import AppKit

nonisolated enum FileShelfEntryInteraction: Equatable {

    case click    (modifiers: NSEvent.ModifierFlags)
    case prepareDrag
    case moveFocus(offset: Int, extendSelection: Bool)
    case delete
    case selectAll
}
