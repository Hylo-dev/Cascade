//
//  AddonRuntimeArchiveShutdownTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing

@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonRuntimeArchiveShutdownTests {
    @Test
    func quiescenceRevokesPublicAuthorityButPreservesPrivateTimelineAndPixelsForCheckpoint() async throws {
        let fixture = try await ArchiveSaveFixture.make()
        defer { fixture.removeFiles() }
        let image = try await fixture.runtime.importAsset(
            encoded      : archiveSavePNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let publication = try Publication(
            id      : fixture.ids[0],
            revision: 1,
            kind    : .widget,
            content : nil,
            timeline: [
                ScheduledEntry(
                    date   : fixture.wall,
                    content: fixture.content(
                        text : "Now",
                        asset: image.assetID
                    )
                ),
                ScheduledEntry(
                    date   : fixture.wall.addingTimeInterval(20),
                    content: fixture.content(
                        text : "Future",
                        asset: image.assetID
                    )
                ),
            ],
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        try await fixture.publish(
            [publication],
            sequence: 1
        )
        let borrowed = await fixture.runtime.assetImage(
            assetID            : image.assetID,
            publicationID      : fixture.ids[0],
            publicationRevision: 1
        )
        #expect(borrowed != nil)
        let ticket = try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10))
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
        #expect(await fixture.runtime.snapshot(at: fixture.wall).isStopped == false)
        #expect(
            await fixture.runtime.assetImage(
                assetID            : image.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            ) == nil
        )
        #expect(
            await fixture.runtime.archiveFlushState(identity: fixture.installed.verifiedIdentity)
                == .unavailable
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.saveArchive(
                owner: fixture.owner,
                to   : fixture.archive
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await fixture.publish(
                [],
                sequence: 2
            )
        }
        let attempt = await fixture.runtime.saveQuiescingArchive(
            owner     : fixture.owner,
            to        : fixture.archive,
            quiescence: ticket
        )
        guard case .committed(let outcome) = attempt else {
            Issue.record("The accepted quiescence did not retain a private checkpoint opportunity.")
            await fixture.stop()
            return
        }
        #expect(outcome.revision == 1)
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(
            try await fixture.matches { envelope in
                guard let json = envelope.records.first?.publication else { return false }
                return try RuntimeArchivePublicationCodec.decode(json) == publication
                    && envelope.blobs.count == 1 && envelope.blobs[0].pixels == Data([255, 0, 0, 255])
            }
        )
        await fixture.stop()
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(borrowed?.width == 1)
    }
    @Test
    func coordinatorRevokesOwnersPerformsOnePassThenReturnsLogicalStopWithoutDraining() async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        let owner     = try await fixture.coordinator.owner(for: fixture.installed[0].verifiedIdentity)
        let beginning = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        #expect(beginning.phase == .ready && beginning.unvisitedOwners == 1)
        await #expect(throws: AddonStorageCoordinator.Failure.self) {
            try await fixture.coordinator.readCheckpoint(owner: owner)
        }
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
        let result = await fixture.coordinator.flushNextShutdownArchive()
        guard
            case .committed(
                let savedOwner,
                let outcome,
                let remaining
            ) = result
        else {
            Issue.record("The shutdown pass did not attempt the dirty owner.")
            await fixture.stop()
            return
        }
        #expect(savedOwner == fixture.owners[0] && outcome.revision == 1 && remaining == 0)
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .exhausted)
        let finished = await fixture.coordinator.finishArchiveShutdown()
        #expect(finished.phase == .terminal && finished.cleanupPending)
        #expect(await fixture.runtime.snapshot(at: fixture.wall).isStopped)
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .windowClosed)
        await fixture.stop()
    }

    @Test
    func ticketsAreOneWayExactAndBoundToTheCurrentMonotonicWindow() async throws {
        let fixture = try await ArchiveSaveFixture.make()
        let foreign = try await ArchiveSaveFixture.make()
        defer {
            fixture.removeFiles()
            foreign.removeFiles()
        }
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.beginArchiveQuiescence(until: .zero)
        }
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.beginArchiveQuiescence(until: .seconds(-1))
        }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        let ticket = try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10))
        #expect(try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10)) == ticket)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.beginArchiveQuiescence(until: .seconds(11))
        }
        let other = try await foreign.runtime.beginArchiveQuiescence(until: .seconds(10))
        #expect(
            await fixture.runtime.saveQuiescingArchive(
                owner     : fixture.owner,
                to        : fixture.archive,
                quiescence: other
            )
                == .refused(.runtime(.permissionDenied))
        )
        #expect(
            await fixture.runtime.saveQuiescingArchive(
                owner     : fixture.owner,
                to        : foreign.archive,
                quiescence: ticket
            )
                == .refused(.runtime(.permissionDenied))
        )
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .seconds(10)
            )
        )
        #expect(
            await fixture.runtime.saveQuiescingArchive(
                owner     : fixture.owner,
                to        : fixture.archive,
                quiescence: ticket
            ) == .windowClosed
        )
        _ = await fixture.runtime.requestStop()
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10))
        }
        await fixture.stop()
        await foreign.stop()
    }

    @Test(arguments: [3, 4])
    func deadlineBoundsRuntimeHandoffAndPreservesAnAlreadyAcceptedBackendCommit(_ gateIndex: Int) async throws
    {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveSaveFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.publish(
            [fixture.publication()],
            sequence: 1
        )
        _ = try await fixture.runtime.saveArchive(
            owner: fixture.owner,
            to   : fixture.archive
        )
        try await fixture.publish(
            [fixture.publication(revision: 2)],
            sequence: 2
        )
        let ticket = try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10))
        await observer.arm(after: gateIndex)
        let saving = Task {
            await fixture.runtime.saveQuiescingArchive(
                owner     : fixture.owner,
                to        : fixture.archive,
                quiescence: ticket
            )
        }
        await observer.waitForArrival()
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .seconds(10)
            )
        )
        if gateIndex == 4 { _ = await fixture.runtime.requestStop() }
        await observer.release()
        let attempt = await saving.value
        if gateIndex == 3 {
            #expect(attempt == .windowClosed)
            #expect(try await fixture.archive.withGeneration { $0?.revision == 1 })
        } else {
            guard case .committed(let outcome) = attempt else {
                Issue.record("The accepted backend commit was relabeled after logical stop.")
                await fixture.stop()
                return
            }
            #expect(outcome.revision == 2)
            #expect(try await fixture.archive.withGeneration { $0?.revision == 2 })
        }
        await fixture.stop()
    }

    @Test
    func exactBusyAndAcceptedQuotaFailureRemainDifferentShutdownResults() async throws {
        let governor = ResourceGovernor()
        let gate     = GatedRuntimeResourceAccess(target: governor)
        let fixture  = try await ArchiveFlushFixture.make(
            governor: governor,
            access  : gate
        )
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        await fixture.runtime.observeExit(fixture.connections[0].incarnation)
        await gate.armResize()
        let assignment = Task {
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
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .busy)
        #expect(
            try await fixture.coordinator.beginArchiveShutdown(
                runtime: fixture.runtime,
                until  : .seconds(10)
            ).unvisitedOwners == 1
        )
        await gate.releaseGate()
        await #expect(throws: AddonFailure.self) { try await assignment.value }
        let before = await governor.usage(.retainedStateBytes)
        let filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - before - 1_024),
            owner: fixture.owners[0]
        )
        let failure = await fixture.coordinator.flushNextShutdownArchive()
        #expect(
            failure
                == .failed(
                    owner          : fixture.owners[0],
                    failure        : .runtime(.resourceDenied),
                    accepted       : true,
                    unvisitedOwners: 0
                )
        )
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .exhausted)
        try await governor.release(
            filler.id,
            owner: fixture.owners[0]
        )
        _ = await fixture.coordinator.finishArchiveShutdown()
        #expect(try await fixture.coordinator.close() == .closed)
        #expect(await fixture.runtime.requestStop().cleanupPending == false)
        await fixture.stop()
    }

    @Test
    func shutdownRetriesSuppressedDebtOnceAndStillVisitsTheNextOwner() async throws {
        let fixture = try await ArchiveFlushFixture.make(count: 2)
        defer { fixture.removeFiles() }
        for index in 0..<2 {
            try await fixture.send(
                index       : index,
                publications: [fixture.publication(index: index)],
                sequence    : 1
            )
        }
        let debt = try await fixture.governor.admitObservedDisk(
            bytes: 0,
            owner: fixture.owners[0]
        )
        _ = try await fixture.governor.reconcileObservedDisk(
            debt,
            owner        : fixture.owners[0],
            fromBytes    : 0,
            measuredBytes: 20 * 1_024 * 1_024
        )
        await #expect(throws: AddonStorageCoordinator.ArchiveFlushFailure.self) {
            try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        }
        #expect(await fixture.state() == .retryRequired)
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        // The shutdown pass starts from C4's cursor, so the second owner is first.
        let first = await fixture.coordinator.flushNextShutdownArchive()
        guard
            case .committed(
                let owner,
                _,
                let remaining
            ) = first
        else {
            Issue.record("The healthy owner was starved.")
            await fixture.stop()
            return
        }
        #expect(owner == fixture.owners[1] && remaining == 1)
        #expect(
            await fixture.coordinator.flushNextShutdownArchive()
                == .failed(
                    owner          : fixture.owners[0],
                    failure        : .runtime(.resourceDenied),
                    accepted       : true,
                    unvisitedOwners: 0
                )
        )
        _ = try await fixture.governor.reconcileObservedDisk(
            debt,
            owner        : fixture.owners[0],
            fromBytes    : 20 * 1_024 * 1_024,
            measuredBytes: 0
        )
        try await fixture.governor.completeObservedDisk(
            debt,
            owner: fixture.owners[0]
        )
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .exhausted)
        _ = await fixture.coordinator.finishArchiveShutdown()
        await fixture.stop()
    }

    @Test
    func cleanAndDisabledRowsConsumeTheFinitePassWithoutCreatingArchives() async throws {
        let fixture = try await ArchiveFlushFixture.make(count: 2)
        defer { fixture.removeFiles() }
        try await fixture.send(
            index       : 1,
            publications: [fixture.publication(index: 1)],
            sequence    : 1
        )
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        await fixture.runtime.disable(owner: fixture.owners[1])
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .exhausted)
        let progress = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        #expect(progress.unvisitedOwners == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.archiveRoot.path).isEmpty)
        _ = await fixture.coordinator.finishArchiveShutdown()
        await fixture.stop()
    }

    @Test
    func beginningDuringHeldKeyedWritePreservesItsOperationAndRevokesOrdinaryCapabilities() async throws {
        let governor = ResourceGovernor()
        let gate     = GatedRuntimeResourceAccess(target: governor)
        let fixture  = try await ArchiveFlushFixture.make(
            governor     : governor,
            storageAccess: gate
        )
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        let owner = try await fixture.coordinator.owner(for: fixture.installed[0].verifiedIdentity)
        await gate.armTemporaryMemory()
        let writing = Task {
            do {
                try await fixture.coordinator.write(
                    Data([8]),
                    key  : "held",
                    owner: owner
                )
            } catch {
                await gate.releaseGate()
                throw error
            }
        }
        await gate.waitForArrival()
        let beginning = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        #expect(beginning.phase == .ready)
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .busy)
        await #expect(throws: AddonStorageCoordinator.Failure.self) {
            try await fixture.coordinator.readCheckpoint(owner: owner)
        }
        await gate.releaseGate()
        await #expect(throws: AddonStorageCoordinator.Failure.self) { try await writing.value }
        guard case .committed = await fixture.coordinator.flushNextShutdownArchive() else {
            Issue.record("The original keyed operation did not release its exact active slot.")
            await fixture.stop()
            return
        }
        _ = await fixture.coordinator.finishArchiveShutdown()
        #expect(try await fixture.coordinator.close() == .closed)
        await fixture.stop()
    }

    @Test
    func knownArchiveCommitSurvivesBeginAndLaterTerminalFinishWithoutReopeningTheContext() async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveFlushFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        try await fixture.send(
            publications: [fixture.publication(revision: 1)],
            sequence    : 2
        )
        await observer.arm(after: 5)
        let saving = Task { try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime) }
        await observer.waitForArrival()
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .busy)
        let finished = await fixture.coordinator.finishArchiveShutdown()
        #expect(finished.phase == .terminal && finished.cleanupPending)
        await observer.release()
        #expect(
            fixture.isCommit(
                try await saving.value,
                ownerIndex: 0,
                revision  : 2
            )
        )
        #expect(
            try await fixture.coordinator.beginArchiveShutdown(
                runtime: fixture.runtime,
                until  : .seconds(10)
            ).phase == .terminal
        )
        await #expect(throws: AddonStorageCoordinator.ArchiveFlushFailure.self) {
            try await fixture.coordinator.beginArchiveShutdown(
                runtime: fixture.runtime,
                until  : .seconds(20)
            )
        }
        await #expect(throws: AddonStorageCoordinator.Failure.self) { try await fixture.coordinator.start() }
        #expect(try await fixture.coordinator.close() == .closed)
        await fixture.stop()
    }

    @Test
    func logicalFinishDoesNotWaitForAnAlreadyHeldGovernorCleanupAndExplicitCloseDrainsRuntime() async throws {
        let governor = ResourceGovernor()
        let gate     = GatedRuntimeResourceAccess(target: governor)
        let fixture  = try await ArchiveFlushFixture.make(
            governor: governor,
            access  : gate
        )
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        #expect(await fixture.coordinator.requestClose() == .draining)
        await gate.armReduction()
        let closing = Task { try await fixture.coordinator.close() }
        await gate.waitForArrival()
        let finished = await fixture.coordinator.finishArchiveShutdown()
        #expect(finished.phase == .terminal && finished.cleanupPending)
        #expect(await fixture.runtime.snapshot(at: fixture.wall).isStopped)
        await gate.releaseGate()
        #expect(try await closing.value == .closed)
        #expect(await fixture.runtime.requestStop().cleanupPending == false)
        #expect(await fixture.coordinator.finishArchiveShutdown().cleanupPending == false)
        await fixture.stop()
    }

    @Test(arguments: ["before", "after", "commit"])
    func quiescenceRejectsCopiedDeferredCompletionAcrossEveryBrokerBoundary(_ boundary: String) async throws {
        let consumer = try installedFixture(
            "consumer",
            publisher: "shared.publisher"
        )
        let provider = try installedFixture(
            "focus",
            publisher: "shared.publisher"
        )
        let governor       = ResourceGovernor()
        let resourceAccess = GatedRuntimeResourceAccess(target: governor)
        let adapter        = RecordingRuntimeAdapter()
        let decisions      = RuntimeServiceDecisionAccessBox()
        let now            = RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .seconds(10)
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [consumer, provider],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [
                    consumer.manifest.id: [],
                    provider.manifest.id: [],
                ],
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : resourceAccess,
            serviceDecisionFactory: { broker in
                let gate = GatedRuntimeServiceDecisionAccess(target: broker)
                decisions.access = gate
                return gate
            },
            adapter: adapter,
            clock  : FixedRuntimeClock(instant: now)
        )
        let offer = try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
        let consumerLaunch     = try await runtime.requestLaunch(owner: consumer.manifest.id)
        let consumerConnection = try await runtime.attach(
            launchID: consumerLaunch,
            offer   : offer
        )
        let permissionID = try await runtime.authorizeService(
            connection   : consumerConnection,
            requirementID: "com.example.focus.sessions",
            scope        : ServiceScope(
                featureID: "summary",
                operation: "read"
            ),
            partition            : "account-a",
            crossPublisherConsent: true
        )
        await #expect(throws: AddonFailure.self) {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
        }
        let providerStart      = try #require(adapter.lastStart(owner: provider.manifest.id))
        let providerConnection = try await runtime.attach(
            launchID: providerStart.launchID,
            offer   : offer
        )
        let acquisition = try await runtime.acquireService(
            connection  : consumerConnection,
            permissionID: permissionID,
            lifetime    : .seconds(30)
        )
        if await governor.usage(
            .jobs,
            owner: provider.manifest.id
        ) == 1 {
            #expect(
                try await runtime.receiveSourceStartupCompletion(
                    acquisition.sourceID,
                    connection: providerConnection
                )
            )
        }
        let work = try await runtime.beginServiceInvocation(
            connection: consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([1]),
                deadline     : now.wall.addingTimeInterval(20)
            )
        )
        #expect(try await runtime.pumpServiceInvocation(work.id))
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data([2])
        )
        let ingress = try #require(
            adapter.stageIngress(
                ProviderOutput(
                    schemaVersion: 1,
                    publications : [],
                    operations   : [],
                    completion   : .service(
                        requestID: work.invocation.requestID,
                        response : response
                    ),
                    checkpoint: nil
                ),
                incarnation: providerConnection.incarnation
            )
        )

        let decisionGate = try #require(decisions.access)
        if boundary == "commit" {
            await resourceAccess.armReduction()
        } else {
            await decisionGate.armCompletionPreparation(beforePreparation: boundary == "before")
        }
        async let completion = runtime.receivePublicationOutput(
            ingress,
            connection: providerConnection,
            sequence  : 1
        )
        if boundary == "commit" {
            await resourceAccess.waitForArrival()
        } else {
            await decisionGate.waitForArrival()
        }
        _ = try await runtime.beginArchiveQuiescence(until: .seconds(40))
        #expect(
            await governor.usage(
                .jobs,
                owner: provider.manifest.id
            ) == 1
        )
        #expect(
            await governor.usage(
                .commands,
                owner: consumer.manifest.id
            ) == 1
        )
        if boundary == "commit" {
            await resourceAccess.releaseGate()
        } else {
            await decisionGate.releaseGate()
        }
        do {
            _ = try await completion
            Issue.record("Quiescence allowed copied deferred completion to activate after broker suspension.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        #expect(
            await governor.usage(
                .commands,
                owner: consumer.manifest.id
            ) == 1
        )
        #expect(
            await governor.usage(
                .jobs,
                owner: provider.manifest.id
            ) == 1
        )
        #expect(adapter.stopCount(incarnation: providerConnection.incarnation) == 1)
        await runtime.observeExit(providerConnection.incarnation)
        #expect(
            await governor.usage(
                .commands,
                owner: consumer.manifest.id
            ) == 0
        )
        #expect(
            await governor.usage(
                .jobs,
                owner: provider.manifest.id
            ) == 0
        )
        _ = await runtime.requestStop()
        await runtime.stop()
        await runtime.observeExit(consumerConnection.incarnation)
    }

    @Test
    func fullStateQuotaStillAllowsImmediateLogicalRevocation() async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        let before = await fixture.governor.usage(.retainedStateBytes)
        let filler = try await fixture.governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - before - 1_024),
            owner: fixture.owners[0]
        )
        _ = try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10))
        let stopped = await fixture.runtime.requestStop()
        #expect(stopped.cleanupPending && stopped.retainedProcessCount == 1)
        #expect(await fixture.coordinator.requestClose() == .draining)
        #expect(await fixture.runtime.snapshot(at: fixture.wall).isStopped)
        try await fixture.governor.release(
            filler.id,
            owner: fixture.owners[0]
        )
        await fixture.runtime.stop()
        #expect(await fixture.runtime.requestStop().cleanupPending == false)
        await fixture.stop()
    }

    @Test
    func expiryAfterOneCaptureDoesNotWrapTheShutdownPassBackToThatOwner() async throws {
        let observer = SaveArchiveObserver()
        let fixture  = try await ArchiveFlushFixture.make(observer: observer)
        defer { fixture.removeFiles() }
        try await fixture.send(
            publications: [fixture.publication()],
            sequence    : 1
        )
        _ = try await fixture.coordinator.flushNextArchive(runtime: fixture.runtime)
        try await fixture.send(
            publications: [fixture.publication(revision: 1)],
            sequence    : 2
        )
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        await observer.arm(after: 4)
        let saving = Task { await fixture.coordinator.flushNextShutdownArchive() }
        await observer.waitForArrival()
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(100),
                monotonic: .seconds(1)
            )
        )
        _ = try? await fixture.runtime.serviceDeadlines()
        await observer.release()
        guard
            case .committed(
                _,
                let outcome,
                let remaining
            ) = await saving.value
        else {
            Issue.record("The already captured generation failed unexpectedly.")
            await fixture.stop()
            return
        }
        #expect(outcome.revision == 2 && remaining == 0)
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .exhausted)
        _ = await fixture.coordinator.finishArchiveShutdown()
        await fixture.stop()
    }

    @Test
    func aLateTicketCannotReopenAContextAlreadyClosedDuringAcquisition() async throws {
        let fixture = try await ArchiveFlushFixture.make()
        defer { fixture.removeFiles() }
        let clock = ShutdownEntryClock(
            instant: RuntimeInstant(
                wall     : fixture.wall,
                monotonic: .zero
            )
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [:],
                explicitBindings: []
            ),
            governor: fixture.governor,
            adapter : RecordingRuntimeAdapter(),
            clock   : clock
        )
        clock.arm()
        defer { clock.release() }
        let beginning = Task {
            try await fixture.coordinator.beginArchiveShutdown(
                runtime: runtime,
                until  : .seconds(10)
            )
        }
        await clock.waitForArrival()
        #expect(await fixture.coordinator.requestClose() == .draining)
        let repeated = try await fixture.coordinator.beginArchiveShutdown(
            runtime: runtime,
            until  : .seconds(10)
        )
        #expect(repeated.phase == .terminal)
        await #expect(throws: AddonStorageCoordinator.ArchiveFlushFailure.self) {
            try await fixture.coordinator.beginArchiveShutdown(
                runtime: fixture.runtime,
                until  : .seconds(10)
            )
        }
        clock.release()
        #expect(try await beginning.value.phase == .terminal)
        #expect(await runtime.snapshot(at: fixture.wall).isStopped)
        #expect(await fixture.coordinator.flushNextShutdownArchive() == .windowClosed)
        #expect(try await fixture.coordinator.close() == .closed)
        await fixture.stop()
    }

    @Test(arguments: [false, true])
    func preAdmissionCleanupCancellationOrExpiryNeverBecomesAnAcceptedFailure(_ expire: Bool) async throws {
        let governor = ResourceGovernor()
        let gate     = GatedRuntimeResourceAccess(target: governor)
        let fixture  = try await ArchiveFlushFixture.make(
            governor: governor,
            access  : gate
        )
        defer { fixture.removeFiles() }
        let publication = try Publication(
            id         : fixture.ids[0],
            revision   : 1,
            kind       : .widget,
            content    : ActionFixture().presentation(),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
        try await fixture.send(
            publications: [publication],
            sequence    : 1
        )
        _ = try await fixture.runtime.submitAction(
            ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : fixture.ids[0],
                actionID        : "pause",
                input           : Data([7]),
                deadline        : fixture.wall.addingTimeInterval(20),
                observedRevision: 1
            )
        )
        _ = try await fixture.coordinator.beginArchiveShutdown(
            runtime: fixture.runtime,
            until  : .seconds(10)
        )
        await gate.armReduction()
        let checkpoint = Task { await fixture.coordinator.flushNextShutdownArchive() }
        await gate.waitForArrival()
        if expire {
            fixture.clock.set(
                RuntimeInstant(
                    wall     : fixture.wall,
                    monotonic: .seconds(10)
                )
            )
        } else {
            checkpoint.cancel()
        }
        await gate.releaseGate()
        let result = await checkpoint.value
        if expire {
            #expect(result == .windowClosed)
        } else {
            #expect(
                result
                    == .failed(
                        owner          : fixture.owners[0],
                        failure        : .cancelled,
                        accepted       : false,
                        unvisitedOwners: 0
                    )
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.archiveRoot.path).isEmpty)
        _ = await fixture.coordinator.finishArchiveShutdown()
        await fixture.stop()
    }

    @Test(arguments: [false, true])
    func shutdownControlStateRequiresItsAdditionalConstructionAllowance(_ coordinator: Bool) async throws {
        let base      = try ActionFixture()
        let installed = try base.context().installed
        let maximum   = coordinator ? 29_952 : 214_272
        let governor  = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: maximum))
        if coordinator {
            let root = URL(fileURLWithPath: "/private/tmp/cascade-shutdown-quota-\(UUID())")
            await #expect(throws: AddonFailure.self) {
                try await AddonStorageCoordinator.make(
                    checkpointRoot: root.appendingPathComponent("checkpoint"),
                    keyedRoot     : root.appendingPathComponent("keyed"),
                    archiveRoot   : root.appendingPathComponent("archive"),
                    registrations : [
                        StateRegistration(
                            identity            : installed.verifiedIdentity,
                            maximumSchemaVersion: 1
                        )
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
                        osVersion: SemanticVersion(
                            14,
                            0,
                            0
                        ),
                        hostCapabilities: [:],
                        applications    : [:],
                        grants          : [base.owner: []],
                        explicitBindings: []
                    ),
                    governor: governor,
                    adapter : RecordingRuntimeAdapter(),
                    clock   : MutableRuntimeClock(
                        instant: RuntimeInstant(
                            wall     : base.wall,
                            monotonic: .zero
                        )
                    )
                )
            }
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

}

/// ShutdownEntryClock parks one synchronous runtime actor entry at a native condition variable.
/// This test-only seam has no sleep or production hook; the test always releases the held entry.
private final class ShutdownEntryClock: RuntimeClock, @unchecked Sendable {
    private let condition = NSCondition()
    private let instant: RuntimeInstant
    private var armed    = false
    private var arrived  = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?

    init(instant: RuntimeInstant) { self.instant = instant }

    func arm() {
        condition.lock()
        armed = true
        released = false
        arrived = false
        condition.unlock()
    }

    func now() -> RuntimeInstant {
        condition.lock()
        if armed {
            armed = false
            arrived = true
            arrival?.resume()
            arrival = nil
            while !released { condition.wait() }
        }
        condition.unlock()
        return instant
    }

    func waitForArrival() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                condition.lock()
                if arrived || released { continuation.resume() } else { arrival = continuation }
                condition.unlock()
            }
        } onCancel: {
            self.release()
        }
    }

    func release() {
        condition.lock()
        released = true
        arrival?.resume()
        arrival = nil
        condition.broadcast()
        condition.unlock()
    }
}
