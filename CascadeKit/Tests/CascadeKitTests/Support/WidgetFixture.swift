//
//  WidgetFixture.swift
//  CascadeKit
//

import SwiftUI
@testable import CascadeKit

/// WidgetFixture is a small widget that keeps the context it was activated with and counts its
/// suspensions and content builds, so a test can poke a retained context after the host is done
/// with it and see which widgets a refresh rebuilt.
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

    /// suspend asks for new content on purpose: a revoked context must swallow the request.
    func suspend() {
        suspensions += 1
        context?.setNeedsContent()
    }
}
