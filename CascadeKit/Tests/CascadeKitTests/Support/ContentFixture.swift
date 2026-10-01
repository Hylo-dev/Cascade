//
//  ContentFixture.swift
//  CascadeKit
//

import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
class ContentFixture: NotchActivity {

    let id                : String
    let sourceID          : String
    var contentRevision   : UInt64 = 0
    var accessibilityLabel: String { id }
    var privacy           : NotchActivityPrivacy { .standard }
    var activations        = 0
    var suspensions        = 0
    var context           : LiveActivityContext?

    init(
        _ id    : String,
        sourceID: String
    ) {
        self.id       = id
        self.sourceID = sourceID
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView { AnyView(Text(id)) }

    func activate(in context: LiveActivityContext) {
        self.context = context
        activations += 1
    }

    func suspend() { suspensions += 1 }
}
