//
//  ReentrantLiveFixture.swift
//  CascadeKit
//

import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ReentrantLiveFixture: ContentFixture, NotchLiveActivity {
    var lifetime = NotchActivityLifetime()
    let relevanceScore: Double = 0.5
    var onActivate: (() -> Void)?

    override func activate(in context: LiveActivityContext) {
        super.activate(in: context)
        onActivate?()
    }
}
