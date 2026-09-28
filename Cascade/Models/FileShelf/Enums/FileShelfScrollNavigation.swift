//
//  FileShelfScrollNavigation.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FileShelfScrollNavigation: Equatable {
    case open
    case close(expectedDirection: FileShelfScrollDirection)
}
