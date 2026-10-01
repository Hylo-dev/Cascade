//
//  AddonRuntimeArchiveFlushTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonRuntimeArchiveFlushTests {

    @Test
    func acceptedRevisionsCoalesceIntoOneGenerationAndRestoreInAFreshRuntime() async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        for revision in 0..<6 {
            try await fixture.send(
                publications: [fixture.publication(revision: UInt64(revision))],
                sequence    : UInt64(revision + 1)
            )
        }

        #expect(await fixture.state() == .pending)
        let result = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        guard case .committed(let owner, let outcome) = result else {
            Issue.record("An accepted canonical change was not flushed.")
            await fixture.stop()
            return
        }

        #expect(owner == fixture.owners[0] && outcome.revision == 1)
        #expect(await fixture.state() == .clean)
        #expect(try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime) == .noCommit)
        await fixture.runtime.observeExit(fixture.connections[0].incarnation)
        await fixture.runtime.stop()
        let restored   = try await fixture.freshRuntime()
        let capability = try await fixture.coordinator.owner(for: fixture.installed[0].verifiedIdentity)
        #expect(
            try await fixture.coordinator.restoreArchive(owner: capability, runtime: restored)
                == .restored(
                    revision: 1,
                    active  : 1,
                    terminal: 0
                )
        )
        #expect(await restored.snapshot(at: fixture.wall).publications.first?.revision == 5)
        #expect(await restored.archiveFlushState(identity: fixture.installed[0].verifiedIdentity) == .clean)
        await restored.stop()
        #expect(try await fixture.coordinator.close() == .closed)
    }

    @Test(arguments: [Publication.Kind.widget, .activity, .notice])
    func sameBatchTerminalHistoryMarksOnlyDurableKinds(_ kind: Publication.Kind) async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication(kind: kind)],
            operations  : [.endPublication(fixture.ids[0])],
            sequence    : 1
        )
        #expect(await fixture.state() == (kind == .notice ? .clean : .pending))
        let result = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        if kind == .notice {
            #expect(result == .noCommit)
        } else {
            #expect(
                fixture.isCommit(
                    result,
                    ownerIndex: 0,
                    revision  : 1
                )
            )
            #expect(await fixture.state() == .clean)
        }

        await fixture.stop()
    }

    @Test
    func noticeEmptyRejectedOutputAndTimelineProjectionDoNotCreatePendingWork() async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.send(publications: [fixture.publication(kind: .notice)], sequence: 1)
        try await fixture.send(sequence: 2)
        _ = await fixture.runtime.snapshot(at: fixture.wall)
        #expect(await fixture.state() == .clean)
        await #expect(throws: (any Error).self) {
            try await fixture.send(publications: [fixture.publication(kind: .notice)], sequence: 3)
        }

        #expect(await fixture.state() == .clean)
        await fixture.stop()

        let timeline = try await ArchiveFlushFixture.make()
        defer { timeline.removeFiles() }
        try await timeline.send(publications: [timeline.publication(timeline: true)], sequence: 1)
        _ = try await timeline.coordinator.flushNextArchive(runtime: timeline.runtime)
        timeline.clock.set(
            RuntimeInstant(wall: timeline.wall.addingTimeInterval(20), monotonic: .seconds(20))
        )
        _ = try await timeline.runtime.serviceDeadlines()
        _ = await timeline.runtime.snapshot(at: timeline.wall.addingTimeInterval(20))
        #expect(await timeline.state() == .clean)
        #expect(try await timeline.coordinator.flushNextArchive(runtime: timeline.runtime) == .noCommit)
        await timeline.stop()
    }

    @Test(arguments: [false, true])
    func expiryOrEndThenPruningReplaceTheOldLiveGeneration(_ expire: Bool) async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.send(publications: [fixture.publication()], sequence: 1)
        _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        if expire {
            fixture.clock.set(
                RuntimeInstant(wall: fixture.wall.addingTimeInterval(100), monotonic: .seconds(100))
            )
            _ = try await fixture.runtime.serviceDeadlines()
        } else {
            try await fixture.send(operations: [.endPublication(fixture.ids[0])], sequence: 2)
        }

        #expect(await fixture.state() == .pending)
        #expect(
            fixture.isCommit(
                try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime),
                ownerIndex: 0,
                revision  : 2
            )
        )
        await fixture.runtime.observeExit(fixture.connections[0].incarnation)
        #expect(await fixture.state() == .clean)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(await fixture.state() == .pending)
        #expect(
            fixture.isCommit(
                try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime),
                ownerIndex: 0,
                revision  : 3
            )
        )
        await fixture.runtime.stop()
        let restored   = try await fixture.freshRuntime()
        let capability = try await fixture.coordinator.owner(for: fixture.installed[0].verifiedIdentity)
        #expect(
            try await fixture.coordinator.restoreArchive(owner: capability, runtime: restored)
                == .restored(
                    revision: 3,
                    active  : 0,
                    terminal: 0
                )
        )
        #expect(await restored.snapshot(at: fixture.wall).publications.isEmpty)
        await restored.stop()
        _ = try await fixture.coordinator.close()
    }

    @Test
    func lazyStartDebtSuppressesOneGenerationAndExplicitSaveRetriesIt() async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.send(publications: [fixture.publication()], sequence: 1)
        let token = try await fixture.governor.admitObservedDisk(bytes: 0, owner: fixture.owners[0])
        _ = try await fixture.governor.reconcileObservedDisk(
            token,
            owner        : fixture.owners[0],
            fromBytes    : 0,
            measuredBytes: 100 * 1_024 * 1_024
        )
        do {
            _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
            Issue.record("Debt unexpectedly admitted lazy archive startup.")
        } catch let error as AddonStorageCoordinator.ArchiveFlushFailure {
            #expect(error == .runtime(.resourceDenied))
        }

        #expect(await fixture.state() == .retryRequired)
        let retained = await fixture.governor.usage(.retainedStateBytes)
        for _ in 0..<4 {
            #expect(try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime) == .noCommit)
        }

        #expect(await fixture.governor.usage(.retainedStateBytes) == retained)
        _ = try await fixture.governor.reconcileObservedDisk(
            token,
            owner        : fixture.owners[0],
            fromBytes    : 100 * 1_024 * 1_024,
            measuredBytes: 0
        )
        try await fixture.governor.completeObservedDisk(token, owner: fixture.owners[0])
        let capability = try await fixture.coordinator.owner(for: fixture.installed[0].verifiedIdentity)
        #expect(try await fixture.coordinator.saveArchive(owner: capability, runtime: fixture.runtime).revision == 1)
        #expect(await fixture.state() == .clean)
        try await fixture.send(publications: [fixture.publication(revision: 1)], sequence: 2)
        #expect(await fixture.state() == .pending)
        await fixture.stop()
    }

    @Test
    func roundRobinReachesTheOtherOwnerAfterFailureAndANewFirstOwnerChange() async throws {
        let fixture = try await ArchiveFlushFixture.make(count: 2)
        defer { fixture.removeFiles() }
        for index in 0..<2 {
            try await fixture.send(
                index       : index,
                publications: [fixture.publication(index: index)],
                sequence    : 1
            )
        }

        let token = try await fixture.governor.admitObservedDisk(bytes: 0, owner: fixture.owners[0])
        _ = try await fixture.governor.reconcileObservedDisk(
            token,
            owner        : fixture.owners[0],
            fromBytes    : 0,
            measuredBytes: 20 * 1_024 * 1_024
        )
        await #expect(throws: AddonStorageCoordinator.ArchiveFlushFailure.self) {
            try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        }

        #expect(await fixture.state() == .retryRequired)
        try await fixture.send(publications: [fixture.publication(revision: 1)], sequence: 2)
        #expect(await fixture.state() == .pending)
        #expect(
            fixture.isCommit(
                try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime),
                ownerIndex: 1,
                revision  : 1
            )
        )
        #expect(await fixture.state(index: 1) == .clean)
        #expect(await fixture.state() == .pending)
        _ = try await fixture.governor.reconcileObservedDisk(
            token,
            owner        : fixture.owners[0],
            fromBytes    : 20 * 1_024 * 1_024,
            measuredBytes: 0
        )
        try await fixture.governor.completeObservedDisk(token, owner: fixture.owners[0])
        #expect(
            fixture.isCommit(
                try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime),
                ownerIndex: 0,
                revision  : 1
            )
        )
        await fixture.stop()
    }

    @Test
    func busyRuntimeLeavesThePendingGenerationEligible() async throws {
        let governor = ResourceGovernor()
        let gate     = GatedRuntimeResourceAccess(target: governor)
        let fixture  = try await ArchiveFlushFixture.make(governor: governor, access: gate)
        defer { fixture.removeFiles() }
        try await fixture.send(publications: [fixture.publication()], sequence: 1)
        await fixture.runtime.observeExit(fixture.connections[0].incarnation)
        #expect(await fixture.state() == .pending)
        await gate.armResize()
        let assigning = Task {
            do {
                return try await fixture.runtime.assignPublication(
                    owner     : fixture.owners[0],
                    featureID : "controls",
                    instanceID: UUID()
                )
            } catch {
                await gate.releaseGate()
                throw error
            }
        }

        await gate.waitForArrival()
        #expect(await fixture.state() == .busy)
        #expect(try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime) == .noCommit)
        await gate.releaseGate()
        _ = try await assigning.value
        #expect(await fixture.state() == .pending)
        _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        #expect(await fixture.state() == .clean)
        await fixture.stop()
    }

    @Test
    func foreignGovernorRefusalPrecedesLazyCreationAndDoesNotConsumePendingWork() async throws {
        let storage  = try await ArchiveFlushFixture.make()
        let provider = try await ArchiveFlushFixture.make()
        defer {
            storage.removeFiles()
            provider.removeFiles()
        }

        try await provider.send(publications: [provider.publication()], sequence: 1)
        do {
            _ = try await storage.coordinator.flushNextArchive(runtime: provider.runtime)
            Issue.record("A foreign governor reached the private archive.")
        } catch let error as AddonStorageCoordinator.ArchiveFlushFailure {
            #expect(error == .runtime(.permissionDenied))
        }

        #expect(await provider.state() == .pending)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.archiveRoot.path).isEmpty)
        _ = try await provider.coordinator.flushNextArchive(runtime: provider.runtime)
        #expect(await provider.state() == .clean)
        await provider.stop()
        await storage.stop()
    }

    @Test(arguments: [false, true])
    func additionalProgressMetadataMustBeAdmittedBeforeReturningAnOwner(_ coordinator: Bool) async throws {
        let base      = try ActionFixture()
        let installed = try base.context().installed
        let oldBytes  = coordinator ? 24_576 + 3_072 + 2 * 1_024 : 208 * 1_024 + 1_024
        let governor  = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: oldBytes))
        if coordinator {
            let root = URL(fileURLWithPath: "/private/tmp/cascade-flush-denial-\(UUID())")
            await #expect(throws: AddonFailure.self) {
                try await AddonStorageCoordinator.make(
                    checkpointRoot: root.appendingPathComponent("checkpoint"),
                    keyedRoot     : root.appendingPathComponent("keyed"),
                    archiveRoot   : root.appendingPathComponent("archive"),
                    registrations : [
                        StateRegistration(identity: installed.verifiedIdentity, maximumSchemaVersion: 1)
                    ],
                    governor: governor
                )
            }

            #expect(!FileManager.default.fileExists(atPath: root.path))
        } else {
            await #expect(throws: AddonFailure.self) {
                try await AddonRuntime.make(
                    catalog    : [installed],
                    environment: HostEnvironment(
                        osVersion       : SemanticVersion(14, 0, 0),
                        hostCapabilities: [:],
                        applications    : [:],
                        grants          : [base.owner: []],
                        explicitBindings: []
                    ),
                    governor: governor,
                    adapter : RecordingRuntimeAdapter(),
                    clock   : MutableRuntimeClock(instant: RuntimeInstant(wall: base.wall, monotonic: .zero))
                )
            }
        }

        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
    }

    @Test(arguments: [false, true])
    func coordinatorCloseOrCancellationCannotRelabelAKnownPendingCommit(_ close: Bool) async throws {
        let observer = FlushArchiveObserver()
        let fixture  = try await ArchiveFlushFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.send(publications: [fixture.publication()], sequence: 1)
        _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        try await fixture.send(publications: [fixture.publication(revision: 1)], sequence: 2)
        await observer.arm(after: 5)
        let flushing = Task { try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime) }
        await observer.waitForArrival()
        if close {
            #expect(try await fixture.coordinator.close() == .draining)
        } else {
            flushing.cancel()
        }

        await observer.release()
        #expect(
            fixture.isCommit(
                try await flushing.value,
                ownerIndex: 0,
                revision  : 2
            )
        )
        #expect(await fixture.state() == .clean)
        await fixture.stop()
    }
}
