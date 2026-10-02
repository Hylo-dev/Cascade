//
//  ManualScheduler.swift
//  CascadeKit
//

/// ManualScheduler keeps the store's delayed work until the test runs it.
@MainActor
final class ManualScheduler {

    private(set) var delays: [Duration] = []
    private var work       : [@MainActor () -> Void] = []

    func schedule(
        _ delay: Duration,
        _ task : @escaping @MainActor () -> Void
    ) {
        delays.append(delay)
        work.append(task)
    }

    /// run performs the delayed task at `index`, as its time had come.
    func run(_ index: Int) {
        work[index]()
    }
}
