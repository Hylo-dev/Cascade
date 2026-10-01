//
//  LiveFixture.swift
//  CascadeKit
//

import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class LiveFixture: ContentFixture, NotchLiveActivity {

    var lifetime       = NotchActivityLifetime()
    let relevanceScore: Double

    init(
        _ id     : String,
        sourceID : String = "media",
        relevance: Double = 0.5
    ) {
        relevanceScore = relevance
        super.init(id, sourceID: sourceID)
    }
}
