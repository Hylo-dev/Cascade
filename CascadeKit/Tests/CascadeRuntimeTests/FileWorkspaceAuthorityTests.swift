//
//  FileWorkspaceAuthorityTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct FileWorkspaceAuthorityTests {
    @Test(arguments: [false, true])
    func builtinAndExternalConsumersUseTheSameCanonicalBoundary(external: Bool) async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let consumer = external ? fixture.external : fixture.builtin
        let admitted = try await fixture.admit(consumer: consumer, broker: broker)
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker   : broker,
            session  : admitted.session,
            grant    : admitted.acquisition.grant,
            command  : .list(cursor: nil)
        )

        let response = try await service.handle(work)

        #expect(try FileWorkspaceSnapshot.decode(response.payload) == fixture.snapshot)
        let call = try #require(await handler.calls.first)
        #expect(call.owner == consumer)
        #expect(call.source.provider == fixture.provider)
        #expect(call.command == .list(cursor: nil))
    }

    @Test func forgedBindingDoesNotDispatchOrRetireLegitimateWork() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let first = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let second = try await fixture.admit(consumer: fixture.external, broker: broker)
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let firstWork = try await fixture.work(
            broker : broker,
            session: first.session,
            grant  : first.acquisition.grant,
            command: .list(cursor: nil)
        )
        let secondWork = try await fixture.work(
            broker : broker,
            session: second.session,
            grant  : second.acquisition.grant,
            command: .cancel(jobID: UUID())
        )
        let forged = ServiceWork(
            id               : firstWork.id,
            sourceID         : secondWork.sourceID,
            invocation       : secondWork.invocation,
            effectiveDeadline: firstWork.effectiveDeadline
        )

        await #expect(throws: AddonFailure.self) {
            _ = try await service.handle(forged)
        }
        #expect(await handler.calls.isEmpty)
        _ = try await service.handle(firstWork)
        _ = try await service.handle(secondWork)
        #expect(await handler.calls.count == 2)
    }

    @Test func rejectsReplayWithoutSecondHandlerCall() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .list(cursor: nil)
        )

        _ = try await service.handle(work)
        await #expect(throws: AddonFailure.self) {
            _ = try await service.handle(work)
        }
        #expect(await handler.calls.count == 1)
    }

    @Test func revocationBeforeDispatchPreventsHandlerInvocation() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .list(cursor: nil)
        )
        _ = await broker.revoke(permissionID: admitted.permissionID)

        await #expect(throws: AddonFailure.self) {
            _ = try await service.handle(work)
        }
        #expect(await handler.calls.isEmpty)
    }

    @Test func staleConnectionGenerationCannotDispatchAfterReconnect() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let stale = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .list(cursor: nil)
        )
        await broker.disconnect(admitted.session)
        let replacementSession = try await broker.registerSession(identity: fixture.builtin)
        let replacement = try await broker.acquire(
            session      : replacementSession,
            requirementID: "files",
            scope        : ServiceScope(
                featureID: "workspace",
                operation: "command"
            ),
            now     : fixture.now,
            lifetime: .seconds(30)
        )

        await #expect(throws: AddonFailure.self) {
            _ = try await service.handle(stale)
        }
        #expect(await handler.calls.isEmpty)
        let current = try await fixture.work(
            broker : broker,
            session: replacementSession,
            grant  : replacement.grant,
            command: .list(cursor: nil)
        )
        _ = try await service.handle(current)
        #expect(await handler.calls.count == 1)
    }

    @Test func revocationDuringHandlerPreventsResultDelivery() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let gate = WorkspaceHandlerGate()
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot, gate: gate)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .list(cursor: nil)
        )
        let pending = Task { try await service.handle(work) }
        await gate.waitForArrival()

        _ = await broker.revoke(permissionID: admitted.permissionID)
        await gate.release()

        await #expect(throws: AddonFailure.self) {
            _ = try await pending.value
        }
        #expect(await handler.calls.count == 1)
    }

    @Test func malformedCommandNeverReachesHandlerAndBecomesUnsent() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let handler = RecordingWorkspaceHandler(snapshot: fixture.snapshot)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            payload: Data([0xFF])
        )

        await #expect(throws: AddonFailure.self) {
            _ = try await service.handle(work)
        }
        #expect(await handler.calls.isEmpty)
        #expect(try await broker.requestOutcome(
            session  : admitted.session,
            grantID  : admitted.acquisition.grant.id,
            requestID: work.invocation.requestID,
            now      : fixture.now
        ) == .unsent)
    }

    @Test func malformedHandlerResponseBecomesUnknownAfterHandoff() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let oversized = try fixture.oversizedSnapshot()
        let handler = RecordingWorkspaceHandler(snapshot: oversized)
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .list(cursor: nil)
        )

        await #expect(throws: AddonFailure.self) {
            _ = try await service.handle(work)
        }
        #expect(await handler.calls.count == 1)
        #expect(try await broker.requestOutcome(
            session  : admitted.session,
            grantID  : admitted.acquisition.grant.id,
            requestID: work.invocation.requestID,
            now      : fixture.now
        ) == .unknown)
    }

    @Test func domainFailureKeepsItsStableCodeAfterHandlerHandoff() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let handler = RecordingWorkspaceHandler(
            snapshot: fixture.snapshot,
            failure : .workspace(.staleRevision)
        )
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .remove(ids: [UUID()], revision: 1)
        )

        do {
            _ = try await service.handle(work)
            Issue.record("Expected the stable workspace failure code.")
        } catch let error as FileWorkspaceError {
            #expect(error == .staleRevision)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(try await broker.requestOutcome(
            session  : admitted.session,
            grantID  : admitted.acquisition.grant.id,
            requestID: work.invocation.requestID,
            now      : fixture.now
        ) == .unknown)
    }

    @Test func untrustedHandlerFailureDoesNotEscapeItsCodeOrText() async throws {
        let fixture = try WorkspaceAuthorityFixture()
        let broker = ServiceBroker()
        let admitted = try await fixture.admit(consumer: fixture.builtin, broker: broker)
        let handler = RecordingWorkspaceHandler(
            snapshot: fixture.snapshot,
            failure : .untrusted(AddonFailure(
                code  : .permissionDenied,
                reason: "Private host path failed."
            ))
        )
        let service = FileWorkspaceService(
            broker : broker,
            handler: handler,
            clock  : FixedWorkspaceClock(fixture.now)
        )
        let work = try await fixture.work(
            broker : broker,
            session: admitted.session,
            grant  : admitted.acquisition.grant,
            command: .list(cursor: nil)
        )

        do {
            _ = try await service.handle(work)
            Issue.record("Expected a sanitized boundary failure.")
        } catch let error as AddonFailure {
            #expect(error.code == .permissionDenied)
            #expect(error.reason != "Private host path failed.")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(try await broker.requestOutcome(
            session  : admitted.session,
            grantID  : admitted.acquisition.grant.id,
            requestID: work.invocation.requestID,
            now      : fixture.now
        ) == .unknown)
    }
}
