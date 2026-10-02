//
//  SpectrumPCMSlot.swift
//  Cascade
//

import Synchronization

/// SpectrumPCMSlot owns one immutable snapshot while its state is ready or reading.
nonisolated final class SpectrumPCMSlot: @unchecked Sendable {

    let left  = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: 2_048)

    var sequence: UInt64 = 0

    private let state = Atomic<Int>(0)

    init() {
        left.initialize(repeating: 0, count: 2_048)
        right.initialize(repeating: 0, count: 2_048)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    func transition(
        from expected: Int,
        to desired   : Int
    ) -> Bool {
        state.compareExchange(
            expected: expected,
            desired : desired,
            ordering: .acquiringAndReleasing
        ).exchanged
    }

    func release(as state: Int) {
        self.state.store(state, ordering: .releasing)
    }
}
