//
//  Settle.swift
//  CascadeKit
//

/// settle waits, for at most five seconds, until an asynchronous refund has reached the
/// governor. Raster disposal refunds off the caller's task once the last reference drops, so
/// under the full parallel run a fixed number of yields can pass before it lands. The caller
/// asserts the settled state afterwards: a refund that never arrives still fails there.
func settle(_ isSettled: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))

    while !(await isSettled()), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
}
