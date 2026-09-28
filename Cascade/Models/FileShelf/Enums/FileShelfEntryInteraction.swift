//
//  FileShelfEntryInteraction.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FileShelfEntryInteraction: Equatable {
    case click(modifiers: NSEvent.ModifierFlags)
    case prepareDrag
    case moveFocus(offset: Int, extendSelection: Bool)
    case delete
    case selectAll
}
