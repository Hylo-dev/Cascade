//
//  verify-caffeinate.swift
//  Cascade
//

import Foundation
import IOKit.pwr_mgt
import Synchronization

/// AssertionFixture records the native boundary while the production actor owns ordering
/// and cleanup. Its mutex allows the check to inspect ownership without racing that actor.
final class AssertionFixture: CaffeinateAssertionManaging, Sendable {

    struct Storage: Sendable {
        var next: UInt32 = 1
        var owned: Set<UInt32> = []
        var displays: [Bool] = []
        var failDisplay = false
        var failRelease = false
    }

    let storage = Mutex(Storage())

    func acquire(keepDisplayAwake: Bool, until: Date?) throws -> UInt32 {
        try storage.withLock { state in
            state.displays.append(keepDisplayAwake)
            if keepDisplayAwake && state.failDisplay { throw CheckFailure.failed }
            let identifier = state.next
            state.next += 1
            state.owned.insert(identifier)
            return identifier
        }
    }

    func release(_ identifier: UInt32) throws {
        try storage.withLock { state in
            if state.failRelease { throw CheckFailure.failed }
            state.owned.remove(identifier)
        }
    }
}

enum CheckFailure: Error {
    case failed
}

/// NativeAssertionFixture observes real power-manager properties without adding test-only
/// introspection to the production owner. A missing OS timeout must fail this check even
/// when the app's own deadline comparison already says the session is over.
final class NativeAssertionFixture: CaffeinateAssertionManaging, Sendable {

    let identifiers = Mutex<[UInt32]>([])
    private let native = IOKitCaffeinateAssertions()

    func acquire(keepDisplayAwake: Bool, until: Date?) throws -> UInt32 {
        let identifier = try native.acquire(keepDisplayAwake: keepDisplayAwake, until: until)
        identifiers.withLock { $0.append(identifier) }
        return identifier
    }

    func release(_ identifier: UInt32) throws { try native.release(identifier) }

    func levels() -> [Int] {
        identifiers.withLock { values in
            values.compactMap { identifier in
                guard let properties = IOPMAssertionCopyProperties(identifier)?.takeRetainedValue() else { return nil }
                let dictionary = properties as NSDictionary
                return (dictionary[kIOPMAssertionLevelKey] as? NSNumber)?.intValue
            }
        }
    }

    func activeCount() throws -> Int {
        var properties: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&properties)
        guard result == kIOReturnSuccess, let properties else { throw CaffeinateFailure.native(result) }
        let processes = properties.takeRetainedValue() as NSDictionary
        let assertions = processes[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] as? [NSDictionary] ?? []
        return assertions.filter {
            ($0[kIOPMAssertionNameKey] as? String)?.hasPrefix("Cascade Caffeinate:") == true
        }.count
    }
}

@main
struct CaffeinateCheck {

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func main() async throws {
        let backend = AssertionFixture()
        let session = CaffeinateSession(backend: backend)
        try require(!(await session.snapshot()).isActive, "Idle must own no assertion")

        try await session.start(keepDisplayAwake: true, until: nil)
        try require((await session.snapshot()).isActive, "Successful acquisition must activate")
        try require(backend.storage.withLock { $0.owned.count == 2 }, "System and display holds are separate")
        try await session.stop()
        try await session.stop()
        try require(backend.storage.withLock { $0.owned.isEmpty }, "Stop must release every hold exactly once")

        backend.storage.withLock { $0.failDisplay = true }
        do {
            try await session.start(keepDisplayAwake: true, until: nil)
            throw NSError(domain: "Display acquisition failure was swallowed", code: 1)
        } catch CheckFailure.failed {}
        try require(!(await session.snapshot()).isActive, "Failed partial start must stay inactive")
        try require(backend.storage.withLock { $0.owned.isEmpty }, "Partial failure must roll back the system hold")

        try await session.start(keepDisplayAwake: false, until: nil)
        do {
            try await session.start(keepDisplayAwake: false, until: Date.distantPast)
            throw NSError(domain: "Expired deadline was accepted", code: 1)
        } catch CaffeinateFailure.invalidDeadline {}
        try require((await session.snapshot()).isActive, "Invalid replacement must preserve the previous session")

        backend.storage.withLock { $0.failRelease = true }
        do {
            try await session.stop()
            throw NSError(domain: "Release failure was swallowed", code: 1)
        } catch CheckFailure.failed {}
        try require((await session.snapshot()).hasResources, "Failed release must retain ownership for a retry")
        backend.storage.withLock { $0.failRelease = false }
        try await session.stop()
        try require(!(await session.snapshot()).hasResources, "A release retry must clean up")

        if CommandLine.arguments.contains("--native") {
            let observer = NativeAssertionFixture()
            let native = CaffeinateSession(backend: observer)
            try await native.start(keepDisplayAwake: true, until: Date.now.addingTimeInterval(2))
            try require((await native.snapshot()).isActive, "Real IOKit acquisition failed")
            try require(observer.levels() == [255, 255], "The OS must hold system and display assertions")
            try require(observer.activeCount() == 2, "powerd must report both assertions active")
            try await Task.sleep(for: .seconds(3))
            try require(!(await native.snapshot()).isActive, "Native deadline must expire")
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while try observer.activeCount() != 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
            }
            try require(observer.activeCount() == 0, "macOS must turn assertions off without an app callback")
            try await native.stop()
            try require(!(await native.snapshot()).hasResources, "Native cleanup failed")
            try require(observer.levels().isEmpty, "Released native IDs must disappear from power manager")
        }
        print("Caffeinate ownership, rollback, deadlines and release checks passed")
    }
}
