//
//  FileShelfScrollDirection.swift
//  Cascade
//

import AppKit
import CascadeKit
import CascadeRuntime
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FileShelfScrollDirection: Equatable {
    case horizontalPositive
    case horizontalNegative
    case verticalPositive
    case verticalNegative

    static let conventionalBack = Self.horizontalPositive

    var inverse: Self {
        switch self {
        case .horizontalPositive: .horizontalNegative
        case .horizontalNegative: .horizontalPositive
        case .verticalPositive: .verticalNegative
        case .verticalNegative: .verticalPositive
        }
    }

    var isHorizontal: Bool {
        switch self {
        case .horizontalPositive, .horizontalNegative: true
        case .verticalPositive, .verticalNegative: false
        }
    }
}
