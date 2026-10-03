//
//  RecordingOptionsAdapter.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadeRuntime

/// RecordingOptionsAdapter models the host's canonical origin registry without
/// hopping to the UI. A copied or wire-constructed token cannot enter the registry.
final class RecordingOptionsAdapter: AddonRuntimeOptionsAdapter, @unchecked Sendable {

    private let lock = NSLock()
    private var origin     : AddonOptionsOrigin?
    private var selected   : AddonOptionsPresentation?
    private var invalidated: Set<UUID> = []
    private var attempts    = 0

    var presentation        : AddonOptionsPresentation? { lock.withLock { selected } }
    var invalidatedLeases   : Set<UUID> { lock.withLock { invalidated } }
    var presentationAttempts: Int { lock.withLock { attempts } }

    func capture(_ origin: AddonOptionsOrigin) {
        lock.withLock { self.origin = origin }
    }

    func accepts(_ origin: AddonOptionsOrigin) -> Bool {
        lock.withLock { self.origin === origin && origin.isValid }
    }

    func present(_ presentation: AddonOptionsPresentation) -> Bool {
        lock.withLock {
            attempts += 1
            guard origin === presentation.origin, presentation.origin.isValid else { return false }
            selected = presentation
            invalidated.remove(presentation.request.leaseID)
            return true
        }
    }

    func invalidateControls(leaseID: UUID, origin: AddonOptionsOrigin) {
        lock.withLock {
            guard selected?.origin === origin else { return }
            invalidated.insert(leaseID)
        }
    }

    func dismiss(leaseID: UUID, origin: AddonOptionsOrigin) {
        lock.withLock {
            guard selected?.request.leaseID == leaseID, selected?.origin === origin else { return }
            selected = nil
        }
    }
}
