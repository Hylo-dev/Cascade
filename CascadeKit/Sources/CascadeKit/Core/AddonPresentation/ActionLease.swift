//
//  ActionLease.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
final class ActionLease {
    private var callback: (@MainActor @Sendable (ActionDescriptor) -> Void)?
    private let expiresAt: Date
    private let now: () -> Date
    init(
        expiresAt: Date = .distantFuture,
        now: @escaping () -> Date = Date.init,
        _ callback: @escaping @MainActor @Sendable (ActionDescriptor) -> Void
    ) {
        self.expiresAt = expiresAt; self.now = now; self.callback = callback
    }
    func dispatch(_ action: ActionDescriptor) {
        guard now() < expiresAt else { callback = nil; return }
        callback?(action)
    }
    func revoke() { callback = nil }
}
