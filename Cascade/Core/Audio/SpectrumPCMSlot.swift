//
//  SpectrumPCMSlot.swift
//  Cascade
//

import Accelerate
import CoreAudio
import AudioToolbox
import Dispatch
import os
import Synchronization

/// SpectrumPCMSlot owns one immutable snapshot while its state is ready or reading.
nonisolated final class SpectrumPCMSlot: @unchecked Sendable {
    let left  = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    var sequence: UInt64 = 0

    private let atomic: AnyObject?
    private let fallbackLock: os_unfair_lock_t
    private var fallbackState = 0

    init() {
        if #available(macOS 15, *) {
            atomic = SpectrumAtomicSlotState()
        } else {
            atomic = nil
        }
        fallbackLock = .allocate(capacity: 1)
        fallbackLock.initialize(to: os_unfair_lock())
        left.initialize(repeating: 0, count: 2_048)
        right.initialize(repeating: 0, count: 2_048)
    }

    deinit {
        left.deallocate()
        right.deallocate()
        fallbackLock.deallocate()
    }

    func transition(from expected: Int, to desired: Int) -> Bool {
        if #available(macOS 15, *), let atomic = atomic as? SpectrumAtomicSlotState {
            return atomic.value.compareExchange(
                expected: expected,
                desired: desired,
                ordering: .acquiringAndReleasing
            ).exchanged
        }
        guard os_unfair_lock_trylock(fallbackLock) else { return false }
        // The legacy lock remains held while the caller owns this slot. A release is therefore
        // an unlock, never a second acquisition that could block the real-time thread.
        guard fallbackState == expected else {
            os_unfair_lock_unlock(fallbackLock)
            return false
        }
        fallbackState = desired
        return true
    }

    func release(as state: Int) {
        if #available(macOS 15, *), let atomic = atomic as? SpectrumAtomicSlotState {
            atomic.value.store(state, ordering: .releasing)
            return
        }
        fallbackState = state
        os_unfair_lock_unlock(fallbackLock)
    }
}

/// SpectrumAtomicSlotState keeps atomic storage behind its platform availability boundary.
@available(macOS 15, *)
nonisolated final class SpectrumAtomicSlotState: Sendable {
    let value = Atomic<Int>(0)
}
