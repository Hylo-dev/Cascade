//
//  SmallStack.swift
//  CascadeKit
//

import Foundation

/// onSmallStack runs `body` on a thread with a 256 KiB stack, half of a secondary thread's
/// default, and returns its result. A decoder that recurses without a bound crashes here.
func onSmallStack(_ body: @escaping @Sendable () -> Bool) -> Bool {
    let done   = DispatchSemaphore(value: 0)
    let result = SmallStackResult()
    let thread = Thread {
        result.value = body()
        done.signal()
    }
    thread.stackSize = 256 * 1_024
    thread.start()
    done.wait()

    return result.value
}

/// SmallStackResult carries the body's result back; the semaphore orders the write and read.
private final class SmallStackResult: @unchecked Sendable {

    var value = false
}
