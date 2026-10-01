//
//  CoordinatorWidgetFixture.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class CoordinatorWidgetFixture: NotchWidget {
    static let kind = WidgetKind("coordinator-widget")
    let id = WidgetIdentifier("coordinator-widget")
    let size = GridSpan.small
    private(set) var activations = 0
    private(set) var suspensions = 0

    func makeContentView() -> AnyView { AnyView(EmptyView()) }
    func activate(in context: WidgetContext) { activations += 1 }
    func suspend() { suspensions += 1 }
}
