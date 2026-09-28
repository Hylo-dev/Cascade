//
//  ActionPermit.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
final class ActionPermit {
    private var callback: (@MainActor @Sendable (ActionDescriptor) -> Void)?
    init(_ callback: @escaping @MainActor @Sendable (ActionDescriptor) -> Void) { self.callback = callback }
    func dispatch(_ action: ActionDescriptor) { callback?(action) }
    func revoke() { callback = nil }
}
