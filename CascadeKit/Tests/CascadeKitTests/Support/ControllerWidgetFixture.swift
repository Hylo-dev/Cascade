//
//  ControllerWidgetFixture.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ControllerWidgetFixture: NotchWidget {
    static let kind = WidgetKind("controller-test")

    let id = WidgetIdentifier("controller-test")
    let size = GridSpan.small
    private(set) var activations = 0
    private(set) var suspensions = 0
    private(set) var factoryCount = 0
    private(set) var factoryRanBeforeActivation = false
    private(set) var context: WidgetContext?

    func makeContentView() -> AnyView {
        factoryCount += 1
        if activations <= suspensions { factoryRanBeforeActivation = true }
        return AnyView(Text("Widget"))
    }
    func activate(in context: WidgetContext) {
        self.context = context
        activations += 1
    }
    func suspend() {
        context = nil
        suspensions += 1
    }
}
