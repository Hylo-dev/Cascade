//
//  WidgetFixture.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import CascadeRuntime
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class WidgetFixture: NotchWidget {

    static let kind = WidgetKind("test")

    let id  : WidgetIdentifier
    let size = GridSpan.small

    var context     : WidgetContext?
    var suspensions  = 0
    var factoryCount = 0

    init(id: String = "test") { self.id = WidgetIdentifier(id) }

    func makeContentView() -> AnyView {
        factoryCount += 1
        return AnyView(EmptyView())
    }

    func activate(in context: WidgetContext) { self.context = context }

    func suspend() {
        suspensions += 1
        context?.setNeedsContent()
    }
}
