//
//  NoticeFixture.swift
//  CascadeKit
//

import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class NoticeFixture: ContentFixture, NotchTransientNotice {
    var displayDuration: TimeInterval = 4
    override init(_ id: String, sourceID: String = "bluetooth") { super.init(id, sourceID: sourceID) }
}
