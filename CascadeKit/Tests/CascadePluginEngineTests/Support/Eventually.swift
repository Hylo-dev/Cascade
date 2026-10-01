//
//  Eventually.swift
//  CascadeKit
//

/// eventually waits, for at most five seconds, until `condition` holds, and returns whether it
/// does. The engine answers on its own queue, so a test polls instead of guessing a delay.
func eventually(_ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }

    return condition()
}
