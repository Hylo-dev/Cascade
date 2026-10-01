//
//  StandaloneFocusProviderTests.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneFocusProvider
import Testing

// Only the public provider and public wire contracts are imported.
private struct UnusedServices: AddonServiceClient {

    func invoke(
        _ invocation: ServiceInvocation,
        grant       : Grant
    ) async throws -> ServiceResponse {
        throw FocusError.invalidConfiguration
    }

    func subscribe(
        requirementID: String,
        grant        : Grant
    ) async throws -> UUID { throw FocusError.invalidConfiguration }

    func unsubscribe(subscriptionID: UUID) async throws { throw FocusError.invalidConfiguration }
}

private final class Clock: @unchecked Sendable {

    private let lock  = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)

    func now() -> Date { lock.withLock { value } }

    func advance(_ seconds: Double) { lock.withLock { value.addTimeInterval(seconds) } }
}

private actor Storage: AddonStorageClient {

    enum Failure: Error {

        case lostReply
    }

    enum WriteMode {

        case normal
        case commitThenThrow
        case throwBeforeCommit
    }

    var data     : Data?
    var writes    = 0
    var reads     = 0
    var mode      = WriteMode.normal
    var failRead  = false
    var gateRead  = false
    var gateWrite = false
    var entered   = false
    var waiter   : CheckedContinuation<Void, Never>?

    func configure(
        _ mode: WriteMode = .normal,
        read  : Bool = false,
        write : Bool = false
    ) {
        self.mode = mode
        gateRead  = read
        gateWrite = write
        entered   = false
    }

    func setReadFailure(_ value: Bool) { failRead = value }

    func replace(_ data: Data?) { self.data = data }

    func snapshot() -> Data? { data }

    func counts() -> (Int, Int) { (reads, writes) }

    func read(key: String) async throws -> Data? {
        #expect(key == StandaloneFocusProvider.storageKey)

        reads += 1
        if failRead { throw Failure.lostReply }

        if gateRead {
            entered = true
            await withCheckedContinuation { waiter = $0 }
        }

        return data
    }

    func write(
        _ data: Data,
        key   : String
    ) async throws {
        #expect(key == StandaloneFocusProvider.storageKey)
        #expect(data.count <= 16_384)

        writes += 1
        if mode == .throwBeforeCommit {
            if gateWrite {
                entered = true
                await withCheckedContinuation { waiter = $0 }
            }
            throw Failure.lostReply
        }

        self.data = data
        if gateWrite {
            entered = true
            await withCheckedContinuation { waiter = $0 }
        }
        if mode == .commitThenThrow { throw Failure.lostReply }
    }

    func remove(key: String) async throws { Issue.record("Provider must not remove state") }

    func release() {
        gateRead  = false
        gateWrite = false
        waiter?.resume()
        waiter = nil
    }

    func waitForEntry() async throws {
        for _ in 0..<100_000 {
            if entered { return }
            await Task.yield()
        }

        throw FocusError.busy
    }
}

private struct Fixture: Sendable {

    let owner  : AddonID
    let id     : PublicationID
    let storage = Storage()
    let clock   = Clock()

    init() throws {
        owner = try #require(AddonID(rawValue: "org.cascade.examples.focus"))
        id    = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    func provider(
        _ mode  : FocusInitializationMode = .freshAssignment,
        duration: Double = 1500
    ) throws -> StandaloneFocusProvider {
        try StandaloneFocusProvider(
            expectedOwner: owner,
            publicationID: id,
            mode         : mode,
            duration     : duration,
            clock        : { clock.now() }
        )
    }

    func context() throws -> AddonContext {
        try AddonContext(
            services  : UnusedServices(),
            storage   : storage,
            generation: ConnectionGeneration(),
            grants    : []
        )
    }

    func action(
        _ name     : String,
        revision   : UInt64,
        requestID  : UUID = UUID(),
        input      : Data = Data(),
        deadline   : Date? = nil,
        publication: PublicationID? = nil
    ) throws -> ActionRequest {
        try ActionRequest(
            schemaVersion   : 1,
            requestID       : requestID,
            publicationID   : publication ?? id,
            actionID        : name,
            input           : input,
            deadline        : deadline ?? clock.now().addingTimeInterval(60),
            observedRevision: revision
        )
    }

    func refresh(_ provider: StandaloneFocusProvider) async throws -> Publication {
        let output = try await provider.handle(.refresh(id), context: context())

        return try #require(output.publications.first)
    }

    func send(
        _ request : ActionRequest,
        _ provider: StandaloneFocusProvider
    ) async throws -> ProviderOutput {
        let output = try await provider.handle(.action(request), context: context())
        try output.validateContext(
            authenticatedAddonID: owner,
            expectedCompletion  : .action(requestID: request.requestID),
            previousRevisions   : [:]
        )
        #expect(output.checkpoint == nil)

        return output
    }
}

private func outcome(_ output: ProviderOutput) throws -> ActionOutcome {
    guard case .action(_, let value) = output.completion else { throw FocusError.corruptState }

    return value
}

private func isRejected(_ output: ProviderOutput) throws -> Bool {
    if case .rejected = try outcome(output) { return true }

    return false
}

private func revision(_ output: ProviderOutput) throws -> UInt64 {
    try #require(output.publications.first).revision
}

private func nodes(_ publication: Publication) -> [ContentNode] {
    func flatten(_ node: ContentNode) -> [ContentNode] { [node] + (node.children ?? []).flatMap(flatten) }

    return publication.content?.widget.map { flatten($0.root) } ?? []
}

private func changeRecord(
    _ data  : Data,
    _ change: (inout [String: Any]) throws -> Void
) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try change(&json)

    return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
}

@Test
func reducerFreezesRemainingAndDoesNotReviveOverdueTimer() throws {
    let now     = Date(timeIntervalSince1970: 1000)
    var session = try FocusSession(duration: 120)

    try session.apply(.start, now: now)
    #expect(session.phase == .running)
    #expect(session.deadline == now.addingTimeInterval(120))

    try session.apply(.pause, now: now.addingTimeInterval(30))
    #expect(session.phase == .paused)
    #expect(session.remaining == 90)
    #expect(session.deadline == nil)

    try session.apply(.resume, now: now.addingTimeInterval(500))
    #expect(session.deadline == now.addingTimeInterval(590))

    try session.reconcile(now: now.addingTimeInterval(600))
    #expect(session.phase == .completed)
    #expect(session.remaining == 0)
    #expect(throws: (any Error).self) { try session.apply(.resume, now: now.addingTimeInterval(601)) }

    try session.apply(.end, now: now.addingTimeInterval(602))
    #expect(session.phase == .ended)
}

@Test
func reducerClampsCivilClockRollbackAndRejectsInvalidDuration() throws {
    let now     = Date(timeIntervalSince1970: 1000)
    var session = try FocusSession(duration: 120)

    try session.apply(.start, now: now)
    try session.apply(.pause, now: now.addingTimeInterval(-600))
    #expect(session.remaining == 120)

    for duration in [0.0, -1, Double.infinity, Double.nan, 86401] {
        #expect(throws: (any Error).self) { _ = try FocusSession(duration: duration) }
    }
}

@Test
func providerLifecycleSurvivesRecreationAndGenerationChange() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()

    let initial = try await fixture.refresh(provider)
    #expect(initial.id == fixture.id)
    #expect(initial.revision == 1)

    let start       = try fixture.action("start", revision: 1)
    let startOutput = try await fixture.send(start, provider)
    #expect(try outcome(startOutput) == .completed(payload: Data()))

    let running = try #require(startOutput.publications.first)
    #expect(running.revision == 2)
    #expect(nodes(running).contains {
        $0.kind == .countdown && $0.deadline == fixture.clock.now().addingTimeInterval(1500)
    })
    #expect(running.expiresAt > fixture.clock.now().addingTimeInterval(1500))
    #expect(startOutput.operations.count == 1)

    let wire = try JSONEncoder().encode(startOutput)
    #expect(try ProviderOutput.decode(wire) == startOutput)

    try startOutput.validateContext(
        authenticatedAddonID: fixture.owner,
        expectedCompletion  : .action(requestID: start.requestID),
        previousRevisions   : [fixture.id: 1]
    )

    fixture.clock.advance(300)
    let recreated = try fixture.provider(.resumeExisting)
    let pause     = try await fixture.send(fixture.action("pause", revision: 2), recreated)
    #expect(try revision(pause) == 3)
    #expect(pause.operations.isEmpty)
    #expect(nodes(try #require(pause.publications.first)).contains { $0.text == "20:00" })

    fixture.clock.advance(600)
    let resume = try await fixture.send(fixture.action("resume", revision: 3), recreated)
    #expect(
        nodes(try #require(resume.publications.first)).contains {
            $0.deadline == fixture.clock.now().addingTimeInterval(1200)
        }
    )
    #expect(resume.operations.count == 1)

    let end = try await fixture.send(fixture.action("end", revision: 4), recreated)
    #expect(try revision(end) == 5)
    #expect(end.operations.isEmpty)
    #expect(nodes(try #require(end.publications.first)).contains { $0.text == "Ended" })
}

@Test
func configuredDurationAndNoOpStartDoNotExtendDeadline() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider(duration: 60)
    _ = try await fixture.refresh(provider)

    let first = try await fixture.send(fixture.action("start", revision: 1), provider)
    fixture.clock.advance(10)

    let second = try await fixture.send(fixture.action("start", revision: 2), provider)
    #expect(second.operations.isEmpty)
    #expect(
        nodes(try #require(first.publications.first)).filter { $0.kind == .countdown }.first?.deadline
            == nodes(try #require(second.publications.first)).filter { $0.kind == .countdown }.first?.deadline
    )
}

@Test
func duplicateReceiptsPrecedeStaleFenceWithoutReplayingRevision() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let request = try fixture.action("start", revision: 1)
    _ = try await fixture.send(request, provider)
    fixture.clock.advance(5)

    let resumedProvider = try fixture.provider(.resumeExisting)
    let duplicate       = try await fixture.send(request, resumedProvider)
    #expect(try outcome(duplicate) == .completed(payload: Data()))
    #expect(try revision(duplicate) == 3)
    #expect(duplicate.operations.isEmpty)

    let changed = try fixture.action(
        "end",
        revision : 1,
        requestID: request.requestID,
        deadline : request.deadline
    )
    let before = await fixture.storage.snapshot()
    #expect(try isRejected(await fixture.send(changed, resumedProvider)))
    #expect(await fixture.storage.snapshot() == before)
    #expect(try isRejected(await fixture.send(fixture.action("pause", revision: 2), resumedProvider)))
}

@Test
func rejectedInputsNeverMutateDurableState() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let before = await fixture.storage.snapshot()
    let other  = PublicationID(
        addonID   : fixture.owner,
        instanceID: UUID(),
        sessionID : fixture.id.sessionID
    )
    let foreign = PublicationID(
        addonID   : try #require(AddonID(rawValue: "other.owner")),
        instanceID: fixture.id.instanceID,
        sessionID : fixture.id.sessionID
    )
    let bad = [
        try fixture.action("reset", revision: 1),
        try fixture.action("start", revision: 1, input: Data([1])),
        try fixture.action("start", revision: 1, deadline: fixture.clock.now()),
        try fixture.action("start", revision: 0),
        try fixture.action("start", revision: 2),
        try fixture.action("start", revision: 1, publication: other),
        try fixture.action("start", revision: 1, publication: foreign),
    ]

    for request in bad {
        #expect(try isRejected(await fixture.send(request, provider)))
        #expect(await fixture.storage.snapshot() == before)
    }
    await #expect(throws: (any Error).self) {
        _ = try await provider.handle(.refresh(other), context: fixture.context())
    }
    #expect(await fixture.storage.snapshot() == before)
}

@Test
func missingResumeAndAssignmentMismatchPreserveState() async throws {
    let fixture = try Fixture()

    let resume = try fixture.provider(.resumeExisting)
    await #expect(throws: FocusError.missingState) { _ = try await fixture.refresh(resume) }

    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let before = await fixture.storage.snapshot()
    let fresh  = try fixture.provider()
    await #expect(throws: FocusError.assignmentMismatch) { _ = try await fixture.refresh(fresh) }

    let newID = PublicationID(
        addonID   : fixture.owner,
        instanceID: fixture.id.instanceID,
        sessionID : UUID()
    )
    let mismatch = try StandaloneFocusProvider(
        expectedOwner: fixture.owner,
        publicationID: newID,
        mode         : .resumeExisting
    )
    await #expect(throws: FocusError.assignmentMismatch) {
        _ = try await mismatch.handle(.refresh(newID), context: fixture.context())
    }
    #expect(await fixture.storage.snapshot() == before)

    await fixture.storage.replace(nil)
    await #expect(throws: FocusError.missingState) { _ = try await fixture.refresh(provider) }
}

@Test
func boundedReceiptsEvictAndFenceOldRetry() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let first = try fixture.action("start", revision: 1)
    _ = try await fixture.send(first, provider)
    for observed in 2...18 {
        _ = try await fixture.send(fixture.action("start", revision: UInt64(observed)), provider)
    }

    let bytes = try #require(await fixture.storage.snapshot())
    #expect(bytes.count <= 16384)

    let record = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect((record["receipts"] as? [Any])?.count == 16)

    let resumed = try fixture.provider(.resumeExisting)
    #expect(try isRejected(await fixture.send(first, resumed)))
    #expect(await fixture.storage.snapshot() == bytes)
}

@Test
func obsoleteAndEarlyExpiryCannotCompleteResumedTimer() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let started = try await fixture.send(fixture.action("start", revision: 1), provider)
    guard case .schedule(_, let oldToken) = try #require(started.operations.first) else {
        throw FocusError.corruptState
    }

    fixture.clock.advance(5)
    _ = try await fixture.send(fixture.action("pause", revision: 2), provider)

    let resumed = try await fixture.send(fixture.action("resume", revision: 3), provider)
    guard case .schedule(_, let token) = try #require(resumed.operations.first) else {
        throw FocusError.corruptState
    }
    #expect(oldToken != token)

    let before = await fixture.storage.snapshot()
    for scheduledToken in [oldToken, token] {
        let output = try await provider.handle(.scheduled(eventID: scheduledToken), context: fixture.context())
        #expect(output.publications.isEmpty)
        #expect(output.operations.isEmpty)
        #expect(await fixture.storage.snapshot() == before)
    }

    fixture.clock.advance(1500)
    let completed = try await provider.handle(.scheduled(eventID: token), context: fixture.context())
    #expect(nodes(try #require(completed.publications.first)).contains { $0.text == "Completed" })
    #expect(completed.operations.isEmpty)

    let after = await fixture.storage.snapshot()
    let again = try await provider.handle(.scheduled(eventID: token), context: fixture.context())
    #expect(again.publications.isEmpty)
    #expect(await fixture.storage.snapshot() == after)
}

@Test
func overdueRefreshRepairsRefusedOutputAndResumeCannotReviveIt() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider(duration: 10)
    _ = try await fixture.refresh(provider)
    _ = try await fixture.send(fixture.action("start", revision: 1), provider)  // Simulated discarded/refused output.

    fixture.clock.advance(20)
    let recreated = try fixture.provider(.resumeExisting, duration: 10)
    let repaired  = try await fixture.refresh(recreated)
    #expect(repaired.revision == 3)
    #expect(nodes(repaired).contains { $0.text == "Completed" })

    let resumeOutput = try await fixture.send(fixture.action("resume", revision: 3), recreated)
    #expect(try isRejected(resumeOutput))
    #expect(resumeOutput.operations.isEmpty)
}

@Test
func uncertainCommittedWriteIsRereadBeforeRetryAndNeverReapplied() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    await fixture.storage.configure(.commitThenThrow)
    let request = try fixture.action("start", revision: 1)
    let unknown = try await fixture.send(request, provider)
    #expect(try outcome(unknown) == .outcomeUnknown)
    #expect(unknown.publications.isEmpty)

    await fixture.storage.configure()
    let retry = try await fixture.send(request, provider)
    #expect(try revision(retry) == 3)
    #expect(try outcome(retry) == .completed(payload: Data()))
    #expect(retry.operations.isEmpty)
    #expect((await fixture.storage.counts()).0 >= 3)
}

@Test
func uncertainUncommittedWriteDoesNotAdvanceRevision() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let before  = await fixture.storage.snapshot()
    let request = try fixture.action("start", revision: 1)
    await fixture.storage.configure(.throwBeforeCommit)
    #expect(try outcome(await fixture.send(request, provider)) == .outcomeUnknown)
    #expect(await fixture.storage.snapshot() == before)

    await fixture.storage.configure()
    let retry = try await fixture.send(request, provider)
    #expect(try revision(retry) == 2)
    #expect(retry.operations.count == 1)
}

@Test
func busyAcrossReadAndCancellationBeforeWriteHasNoEffect() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let before = await fixture.storage.snapshot()
    await fixture.storage.configure(read: true)

    let request = try fixture.action("start", revision: 1)
    let task    = Task { try await fixture.send(request, provider) }
    try await fixture.storage.waitForEntry()
    await #expect(throws: FocusError.busy) { _ = try await fixture.refresh(provider) }

    task.cancel()
    await fixture.storage.release()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await fixture.storage.snapshot() == before)
}

@Test
func successfulWriteIsNotUndoneByCancellationAndBusySpansWrite() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    await fixture.storage.configure(write: true)
    let task = Task { try await fixture.send(fixture.action("start", revision: 1), provider) }
    try await fixture.storage.waitForEntry()
    await #expect(throws: FocusError.busy) { _ = try await fixture.refresh(provider) }

    task.cancel()
    await fixture.storage.release()

    let committed = try await task.value
    #expect(try outcome(committed) == .completed(payload: Data()))
    #expect(try revision(committed) == 2)
    #expect(try await fixture.refresh(fixture.provider(.resumeExisting)).revision == 3)
}

@Test
func cancelledAmbiguousCommitStillReportsUnknown() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    await fixture.storage.configure(.commitThenThrow, write: true)
    let request = try fixture.action("start", revision: 1)
    let task    = Task { try await fixture.send(request, provider) }
    try await fixture.storage.waitForEntry()

    task.cancel()
    await fixture.storage.release()
    #expect(try outcome(await task.value) == .outcomeUnknown)

    await fixture.storage.configure()
    #expect(try revision(await fixture.send(request, fixture.provider(.resumeExisting))) == 3)
}

@Test
func corruptFutureOversizedAndInconsistentRecordsAreNeverOverwritten() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let good       = try #require(await fixture.storage.snapshot())
    let candidates = [
        Data("not json".utf8),
        Data(repeating: 32, count: 16385),
        try changeRecord(good) { $0["schemaVersion"] = 2 },
        try changeRecord(good) { $0["revision"] = -1 },
        try changeRecord(good) { $0["session"] = ["phase": "running", "duration": 1500, "remaining": 1500] },
        try changeRecord(good) { $0["receipts"] = Array(repeating: [:], count: 17) },
    ]

    for bytes in candidates {
        await fixture.storage.replace(bytes)
        let resumed = try fixture.provider(.resumeExisting)
        await #expect(throws: (any Error).self) { _ = try await fixture.refresh(resumed) }
        #expect(await fixture.storage.snapshot() == bytes)
    }
}

@Test
func revisionExhaustionFailsBeforeStorageOrPublication() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let original = try #require(await fixture.storage.snapshot())
    let bytes    = try changeRecord(original) { $0["revision"] = NSNumber(value: UInt64.max) }
    await fixture.storage.replace(bytes)

    let resumed = try fixture.provider(.resumeExisting)
    await #expect(throws: FocusError.revisionExhausted) { _ = try await fixture.refresh(resumed) }
    #expect(await fixture.storage.snapshot() == bytes)
}

@Test
func stopIsEmptyWithoutFlushAndTerminatesAuthority() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let before  = await fixture.storage.snapshot()
    let stopped = try await provider.handle(.stop(.permissionRevoked), context: fixture.context())
    #expect(
        stopped.publications.isEmpty && stopped.operations.isEmpty && stopped.completion == nil
            && stopped.checkpoint == nil
    )
    #expect(await fixture.storage.snapshot() == before)
    await #expect(throws: FocusError.stopped) { _ = try await fixture.refresh(provider) }
}

@Test
func sourceManifestMatchesImplementedPublicBoundary() throws {
    let url      = try #require(Bundle.module.url(forResource: "Manifest", withExtension: "json"))
    let manifest = try AddonManifest.decode(Data(contentsOf: url))

    #expect(
        manifest.sourceApp == nil && manifest.requires.isEmpty && manifest.provides.isEmpty
            && manifest.bundledLibraries.isEmpty
    )
    #expect(manifest.features.flatMap { $0.actions ?? [] } == ["start", "pause", "resume", "end"])
    #expect(manifest.permissions.map(\.id) == [.storageOwn])
    #expect(manifest.resources.background == .scheduledDeadline)
}

@Test
func overdueStateIsReconciledUsingClockAfterStorageAwait() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider(duration: 10)
    _ = try await fixture.refresh(provider)
    _ = try await fixture.send(fixture.action("start", revision: 1), provider)

    await fixture.storage.configure(read: true)
    let task = Task { try await fixture.send(fixture.action("pause", revision: 2), provider) }
    try await fixture.storage.waitForEntry()

    fixture.clock.advance(20)
    await fixture.storage.release()

    let result = try await task.value
    #expect(try isRejected(result))
    #expect(nodes(try #require(result.publications.first)).contains { $0.text == "Completed" })
    #expect(result.operations.isEmpty)
}

@Test
func deadlineExpiringDuringReadPreventsStorageHandoff() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let before  = await fixture.storage.snapshot()
    let counts  = await fixture.storage.counts()
    let request = try fixture.action(
        "start",
        revision: 1,
        deadline: fixture.clock.now().addingTimeInterval(5)
    )
    await fixture.storage.configure(read: true)

    let task = Task { try await fixture.send(request, provider) }
    try await fixture.storage.waitForEntry()

    fixture.clock.advance(10)
    await fixture.storage.release()
    #expect(try isRejected(await task.value))
    #expect(await fixture.storage.snapshot() == before)
    #expect((await fixture.storage.counts()).1 == counts.1)
}

@Test
func unknownPersistedFieldsAndAssignmentPayloadAreCorruption() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)
    _ = try await fixture.send(fixture.action("start", revision: 1), provider)

    let original     = try #require(await fixture.storage.snapshot())
    let extraReceipt = try changeRecord(original) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        receipts[0]["unexpected"] = 1
        json["receipts"]          = receipts
    }
    let extraAssignment = try changeRecord(original) { json in
        var assignment = try #require(json["assignment"] as? [String: Any])
        assignment["unexpected"] = 1
        json["assignment"]       = assignment
    }
    let extraRequest = try changeRecord(original) { json in
        var receipts   = try #require(json["receipts"] as? [[String: Any]])
        var request    = try #require(receipts[0]["request"] as? [String: Any])
        var assignment = try #require(request["publicationID"] as? [String: Any])

        assignment["unexpected"] = 1
        request["publicationID"] = assignment
        receipts[0]["request"]   = request
        json["receipts"]         = receipts
    }

    for data in [extraReceipt, extraAssignment, extraRequest] {
        await fixture.storage.replace(data)
        let resumed = try fixture.provider(.resumeExisting)
        await #expect(throws: FocusError.corruptState) { _ = try await fixture.refresh(resumed) }
        #expect(await fixture.storage.snapshot() == data)
    }
}

@Test
func failedRereadAfterUncertainWriteBlocksMutationUntilAuthoritativeRead() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let request = try fixture.action("start", revision: 1)
    await fixture.storage.configure(.commitThenThrow)
    #expect(try outcome(await fixture.send(request, provider)) == .outcomeUnknown)

    let committed = await fixture.storage.snapshot()
    let counts    = await fixture.storage.counts()
    await fixture.storage.configure()
    await fixture.storage.setReadFailure(true)

    let unreadable = try await fixture.send(request, provider)
    #expect(try outcome(unreadable) == .outcomeUnknown)
    #expect(unreadable.publications.isEmpty && unreadable.operations.isEmpty && unreadable.checkpoint == nil)
    #expect(await fixture.storage.snapshot() == committed)
    #expect((await fixture.storage.counts()).1 == counts.1)

    await fixture.storage.setReadFailure(false)
    #expect(try revision(await fixture.send(request, provider)) == 3)
}

@Test
func uncertainRefreshReservesGapAndMissingStateStillFailsClosed() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()

    await fixture.storage.configure(.commitThenThrow)
    await #expect(throws: (any Error).self) { _ = try await fixture.refresh(provider) }

    await fixture.storage.configure()
    #expect(try await fixture.refresh(provider).revision == 2)

    await fixture.storage.replace(nil)
    await #expect(throws: FocusError.missingState) { _ = try await fixture.refresh(provider) }
}

@Test
func changedFingerprintDeadlineAndRevisionCannotReuseReceipt() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let request = try fixture.action("start", revision: 1)
    _ = try await fixture.send(request, provider)

    let before = await fixture.storage.snapshot()
    for changed in [
        try fixture.action(
            "start",
            revision : 2,
            requestID: request.requestID,
            deadline : request.deadline
        ),
        try fixture.action(
            "start",
            revision : 1,
            requestID: request.requestID,
            deadline : request.deadline.addingTimeInterval(1)
        ),
    ] {
        #expect(try isRejected(await fixture.send(changed, provider)))
        #expect(await fixture.storage.snapshot() == before)
    }
}

@Test
func configurationMismatchAndInvalidClockNeverWrite() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider(duration: 60)
    _ = try await fixture.refresh(provider)

    let before = await fixture.storage.snapshot()
    let wrong  = try fixture.provider(.resumeExisting, duration: 120)
    await #expect(throws: FocusError.invalidConfiguration) { _ = try await fixture.refresh(wrong) }

    let badClock = try StandaloneFocusProvider(
        expectedOwner: fixture.owner,
        publicationID: fixture.id,
        mode         : .resumeExisting,
        duration     : 60,
        clock        : { Date(timeIntervalSince1970: .infinity) }
    )
    await #expect(throws: FocusError.invalidConfiguration) { _ = try await fixture.refresh(badClock) }
    #expect(await fixture.storage.snapshot() == before)
}

@Test
func overduePauseRejectionReceiptIsStableAcrossRecreation() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider(duration: 10)
    _ = try await fixture.refresh(provider)
    _ = try await fixture.send(fixture.action("start", revision: 1), provider)

    fixture.clock.advance(20)
    let pause   = try fixture.action("pause", revision: 2)
    let refused = try await fixture.send(pause, provider)
    #expect(try isRejected(refused))
    #expect(nodes(try #require(refused.publications.first)).contains { $0.text == "Completed" })

    let duplicate = try await fixture.send(pause, fixture.provider(.resumeExisting, duration: 10))
    #expect(try outcome(duplicate) == outcome(refused))
    #expect(try revision(duplicate) == 4)
    #expect(duplicate.operations.isEmpty)
}

// A controlled pair of reads demonstrates the public storage API's lack of CAS.
private actor CompetingStorage: AddonStorageClient {

    var data : Data
    var reads: [CheckedContinuation<Data?, any Error>] = []

    init(_ data: Data) { self.data = data }

    func read(key: String) async throws -> Data? {
        #expect(key == StandaloneFocusProvider.storageKey)

        return try await withCheckedThrowingContinuation { continuation in
            reads.append(continuation)
            if reads.count == 2 {
                let snapshot = data
                for waitingRead in reads { waitingRead.resume(returning: snapshot) }
                reads.removeAll()
            }
        }
    }

    func write(
        _ data: Data,
        key   : String
    ) async throws {
        #expect(data.count <= 16_384)

        self.data = data
    }

    func remove(key: String) async throws { Issue.record("Unexpected remove") }
}

@Test
func competingProvidersRequireHostSerializationRatherThanClaimingCAS() async throws {
    let fixture = try Fixture()
    _ = try await fixture.refresh(fixture.provider())

    let shared  = CompetingStorage(try #require(await fixture.storage.snapshot()))
    let context = try AddonContext(
        services  : UnusedServices(),
        storage   : shared,
        generation: ConnectionGeneration(),
        grants    : []
    )

    let leftProvider  = try fixture.provider(.resumeExisting)
    let rightProvider = try fixture.provider(.resumeExisting)
    let start         = try fixture.action("start", revision: 1)
    let end           = try fixture.action("end", revision: 1)

    async let left  = leftProvider.handle(.action(start), context: context)
    async let right = rightProvider.handle(.action(end), context: context)
    let (leftOutput, rightOutput) = try await (left, right)

    #expect(try revision(leftOutput) == 2)
    #expect(try revision(rightOutput) == 2)
    #expect(try outcome(leftOutput) == .completed(payload: Data()))
    #expect(try outcome(rightOutput) == .completed(payload: Data()))
    #expect(throws: (any Error).self) {
        try rightOutput.validateContext(
            authenticatedAddonID: fixture.owner,
            expectedCompletion  : .action(requestID: end.requestID),
            previousRevisions   : [fixture.id: 2]
        )
    }
}

@Test
func malformedReceiptsAndPhaseTokenMismatchPreserveBytes() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)
    _ = try await fixture.send(fixture.action("start", revision: 1), provider)

    let good         = try #require(await fixture.storage.snapshot())
    let badToken     = try changeRecord(good) { $0["activeToken"] = "unknown" }
    let missingToken = try changeRecord(good) { $0.removeValue(forKey: "activeToken") }
    let badRemaining = try changeRecord(good) { json in
        var session = try #require(json["session"] as? [String: Any])
        session["remaining"] = -1
        json["session"]      = session
    }
    let tooNewReceipt = try changeRecord(good) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        receipts[0]["revision"] = 3
        json["receipts"]        = receipts
    }
    let duplicateReceipt = try changeRecord(good) { json in
        let receipts = try #require(json["receipts"] as? [[String: Any]])
        json["receipts"] = receipts + receipts
    }
    let nonemptyInput = try changeRecord(good) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        var request  = try #require(receipts[0]["request"] as? [String: Any])

        request["input"]       = "AQ=="
        receipts[0]["request"] = request
        json["receipts"]       = receipts
    }
    let unknownOutcome = try changeRecord(good) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        receipts[0]["outcome"] = ["outcomeUnknown": [:]]
        json["receipts"]       = receipts
    }

    for bytes in [
        badToken,
        missingToken,
        badRemaining,
        tooNewReceipt,
        duplicateReceipt,
        nonemptyInput,
        unknownOutcome
    ] {
        await fixture.storage.replace(bytes)
        await #expect(throws: FocusError.corruptState) {
            _ = try await fixture.refresh(fixture.provider(.resumeExisting))
        }
        #expect(await fixture.storage.snapshot() == bytes)
    }
}

@Test
func refreshesReserveRevisionsWithoutDuplicatingScheduleWork() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)
    _ = try await fixture.send(fixture.action("start", revision: 1), provider)

    for wanted in 3...5 {
        let output = try await provider.handle(.refresh(fixture.id), context: fixture.context())
        #expect(try revision(output) == UInt64(wanted))
        #expect(output.operations.isEmpty)

        try output.validateContext(
            authenticatedAddonID: fixture.owner,
            expectedCompletion  : nil,
            previousRevisions   : [fixture.id: UInt64(wanted - 1)]
        )
    }

    #expect(try isRejected(await fixture.send(fixture.action("pause", revision: 2), provider)))
}

@Test
func retainedCommittedReceiptOutlivesDeadlineWithoutReapplyingCommand() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let request = try fixture.action(
        "start",
        revision: 1,
        deadline: fixture.clock.now().addingTimeInterval(5)
    )
    let original         = try await fixture.send(request, provider)
    let originalDeadline = nodes(try #require(original.publications.first)).first { $0.kind == .countdown }?.deadline

    fixture.clock.advance(10)
    let recreated = try fixture.provider(.resumeExisting)
    let late      = try await fixture.send(request, recreated)
    #expect(try outcome(late) == .completed(payload: Data()))
    #expect(try revision(late) == 3)
    #expect(late.operations.isEmpty)
    #expect(nodes(try #require(late.publications.first)).first { $0.kind == .countdown }?.deadline == originalDeadline)

    let before  = await fixture.storage.snapshot()
    let changed = try fixture.action(
        "end",
        revision : 1,
        requestID: request.requestID,
        deadline : request.deadline
    )
    #expect(try isRejected(await fixture.send(changed, recreated)))
    #expect(await fixture.storage.snapshot() == before)

    fixture.clock.advance(2000)
    let overdue = try await fixture.send(request, recreated)
    #expect(try outcome(overdue) == .completed(payload: Data()))
    #expect(try revision(overdue) == 4)
    #expect(nodes(try #require(overdue.publications.first)).contains { $0.text == "Completed" })
    #expect(overdue.operations.isEmpty)
}

@Test
func recreatedProviderReadFailureCannotRejectKnownOrPotentiallyCommittedAction() async throws {
    for rejectedReceipt in [false, true] {
        let fixture = try Fixture()
        let initial = try fixture.provider()
        _ = try await fixture.refresh(initial)

        let request = try fixture.action(
            rejectedReceipt ? "pause" : "start",
            revision: 1,
            deadline: fixture.clock.now().addingTimeInterval(5)
        )
        let committed       = try await fixture.send(request, initial)  // Output could be lost after the known commit.
        let originalOutcome = try outcome(committed)
        let bytes           = await fixture.storage.snapshot()
        let before          = await fixture.storage.counts()

        fixture.clock.advance(10)
        let recreated = try fixture.provider(.resumeExisting)
        await fixture.storage.setReadFailure(true)

        let unreadable = try await fixture.send(request, recreated)
        #expect(try outcome(unreadable) == .outcomeUnknown)
        #expect(unreadable.publications.isEmpty && unreadable.operations.isEmpty && unreadable.checkpoint == nil)
        #expect(await fixture.storage.snapshot() == bytes)
        #expect((await fixture.storage.counts()).1 == before.1)

        // Even a different valid intent cannot prove absence of its own receipt while reads fail.
        let unobserved = try fixture.action("end", revision: 2)
        #expect(try outcome(await fixture.send(unobserved, recreated)) == .outcomeUnknown)

        // Proven invalid input still refuses before lookup.
        #expect(try isRejected(await fixture.send(fixture.action("reset", revision: 2), recreated)))
        #expect((await fixture.storage.counts()).1 == before.1)

        await fixture.storage.setReadFailure(false)
        let recovered = try await fixture.send(request, recreated)
        #expect(try outcome(recovered) == originalOutcome)
        #expect(try revision(recovered) == 3)
        #expect(recovered.operations.isEmpty)

        if !rejectedReceipt {
            #expect(
                nodes(try #require(recovered.publications.first)).first { $0.kind == .countdown }?.deadline
                    == nodes(try #require(committed.publications.first)).first { $0.kind == .countdown }?.deadline
            )
        }
    }
}

@Test
func nestedUnknownRejectedFailureKeysRefusePublicResumeWithoutOverwriting() async throws {
    let fixture  = try Fixture()
    let provider = try fixture.provider()
    _ = try await fixture.refresh(provider)

    let request = try fixture.action("pause", revision: 1)
    let refused = try await fixture.send(request, provider)
    #expect(try isRejected(refused))

    let original = try #require(await fixture.storage.snapshot())
    let corrupt  = try changeRecord(original) { json in
        var receipts      = try #require(json["receipts"] as? [[String: Any]])
        var actionOutcome = try #require(receipts[0]["outcome"] as? [String: Any])
        var rejected      = try #require(actionOutcome["rejected"] as? [String: Any])
        var reason        = try #require(rejected["reason"] as? [String: Any])

        reason["unexpected"]      = 1
        rejected["reason"]        = reason
        actionOutcome["rejected"] = rejected
        receipts[0]["outcome"]    = actionOutcome
        json["receipts"]          = receipts
    }
    await fixture.storage.replace(corrupt)

    let before  = await fixture.storage.counts()
    let resumed = try fixture.provider(.resumeExisting)
    await #expect(throws: FocusError.corruptState) { _ = try await fixture.refresh(resumed) }
    #expect(await fixture.storage.snapshot() == corrupt)
    #expect((await fixture.storage.counts()).1 == before.1)
}

@Test
func recoveredReceiptRemainsKnownAcrossAmbiguousSnapshotWrites() async throws {
    // 16 cases: completed/rejected x uncommitted/committed x late/overdue x cancellation/no cancellation.
    for rejectedReceipt in [false, true] {
        for commitsSnapshot in [false, true] {
            for overdue in [false, true] {
                for cancelled in [false, true] {
                    let fixture = try Fixture()
                    let initial = try fixture.provider()
                    _ = try await fixture.refresh(initial)

                    let request = try fixture.action(
                        rejectedReceipt ? "pause" : "start",
                        revision: 1,
                        deadline: fixture.clock.now().addingTimeInterval(5)
                    )
                    let original = try await fixture.send(request, initial)
                    let known   : ActionOutcome =
                        rejectedReceipt
                        ? .rejected(
                            reason: AddonFailure(
                                code  : .invalidPayload,
                                reason: "Command unavailable in current phase"
                            )
                        )
                        : .completed(payload: Data())
                    #expect(try outcome(original) == known)

                    // Give both original receipt kinds an active timer whose reconciliation can be uncertain.
                    if rejectedReceipt { _ = try await fixture.send(fixture.action("start", revision: 2), initial) }

                    let highWater    : UInt64 = rejectedReceipt ? 3 : 2
                    let beforeBytes   = try #require(await fixture.storage.snapshot())
                    let beforeJSON    = try #require(JSONSerialization.jsonObject(with: beforeBytes) as? [String: Any])
                    let beforeSession = try #require(beforeJSON["session"] as? [String: Any])
                    let timerID       = try #require(beforeSession["timerID"] as? String)

                    fixture.clock.advance(overdue ? 1600 : 10)
                    let recreated = try fixture.provider(.resumeExisting)
                    await fixture.storage.configure(
                        commitsSnapshot ? .commitThenThrow : .throwBeforeCommit,
                        write: cancelled
                    )

                    let duplicate = Task { try await fixture.send(request, recreated) }
                    if cancelled {
                        try await fixture.storage.waitForEntry()
                        duplicate.cancel()
                        await fixture.storage.release()
                    }

                    let result = try await duplicate.value
                    #expect(result.completion == .action(requestID: request.requestID, outcome: known))
                    #expect(result.publications.isEmpty && result.operations.isEmpty && result.checkpoint == nil)

                    let afterBytes = try #require(await fixture.storage.snapshot())
                    if !commitsSnapshot { #expect(afterBytes == beforeBytes) }

                    let afterJSON = try #require(JSONSerialization.jsonObject(with: afterBytes) as? [String: Any])
                    let session   = try #require(afterJSON["session"] as? [String: Any])
                    #expect(session["timerID"] as? String == timerID)
                    #expect(session["phase"] as? String == (commitsSnapshot && overdue ? "completed" : "running"))

                    let attempts = await fixture.storage.counts()
                    // A recovered receipt still rejects a changed fingerprint; no new write is attempted.
                    let changed = try fixture.action(
                        "end",
                        revision : 1,
                        requestID: request.requestID,
                        deadline : request.deadline
                    )
                    #expect(try isRejected(await fixture.send(changed, recreated)))
                    #expect((await fixture.storage.counts()).1 == attempts.1)
                    #expect(await fixture.storage.snapshot() == afterBytes)

                    await fixture.storage.configure()
                    let beforeRefresh = await fixture.storage.counts()
                    let repaired      = try await recreated.handle(.refresh(fixture.id), context: fixture.context())
                    #expect((await fixture.storage.counts()).0 == beforeRefresh.0 + 1)
                    #expect(try revision(repaired) == highWater + (commitsSnapshot ? 2 : 1))
                    #expect(repaired.operations.isEmpty)

                    let publication = try #require(repaired.publications.first)
                    if overdue {
                        #expect(nodes(publication).contains { $0.text == "Completed" })
                    } else {
                        #expect(
                            nodes(publication).first { $0.kind == .countdown }?.deadline
                                == Date(timeIntervalSince1970: 2_000_001_500)
                        )
                    }

                    let retry = try await fixture.send(request, recreated)
                    #expect(try outcome(retry) == known)
                    #expect(try revision(retry) == highWater + (commitsSnapshot ? 3 : 2))
                    #expect(retry.operations.isEmpty)
                }
            }
        }
    }
}

// Invalid history must not turn a potentially committed command into a proven rejection.
private func assertUnusableHistoryPreservesUncertainty(
    fixture      : Fixture,
    request      : ActionRequest,
    original     : ProviderOutput,
    originalBytes: Data,
    unusable     : Data?,
    diagnostic   : FocusError,
    mode         : FocusInitializationMode = .resumeExisting,
    duration     : Double = 1500
) async throws {
    await fixture.storage.replace(unusable)

    let provider = try fixture.provider(mode, duration: duration)
    let before   = await fixture.storage.counts()
    let unknown  = try await fixture.send(request, provider)
    #expect(unknown.completion == .action(requestID: request.requestID, outcome: .outcomeUnknown))
    #expect(unknown.publications.isEmpty && unknown.operations.isEmpty && unknown.checkpoint == nil)
    #expect(await fixture.storage.snapshot() == unusable)
    #expect((await fixture.storage.counts()).1 == before.1)

    await #expect(throws: diagnostic) { _ = try await fixture.refresh(provider) }
    #expect(await fixture.storage.snapshot() == unusable)
    #expect((await fixture.storage.counts()).1 == before.1)

    // Request validation remains independent of the unusable ledger.
    #expect(try isRejected(await fixture.send(fixture.action("reset", revision: 2), provider)))

    let foreign = PublicationID(
        addonID   : fixture.owner,
        instanceID: UUID(),
        sessionID : fixture.id.sessionID
    )
    #expect(try isRejected(await fixture.send(fixture.action("start", revision: 2, publication: foreign), provider)))
    #expect((await fixture.storage.counts()).0 == before.0 + 2)
    #expect((await fixture.storage.counts()).1 == before.1)

    // Only an external restoration repairs the ledger; the provider never repairs it itself.
    await fixture.storage.replace(originalBytes)

    let recovered = try await fixture.send(request, fixture.provider(.resumeExisting))
    #expect(try outcome(recovered) == outcome(original))
    #expect(try revision(recovered) == 3)
    #expect(recovered.operations.isEmpty)

    let originalRecord   = try #require(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
    let recoveredBytes   = try #require(await fixture.storage.snapshot())
    let recoveredRecord  = try #require(JSONSerialization.jsonObject(with: recoveredBytes) as? [String: Any])
    let originalSession  = try #require(originalRecord["session"] as? NSDictionary)
    let recoveredSession = try #require(recoveredRecord["session"] as? NSDictionary)
    #expect(originalSession == recoveredSession)  // No restart, new timer ID, deadline extension or phase command replay.
}

@Test
func malformedUnsupportedAndInvalidHistoryLeaveCommittedActionUnknown() async throws {
    for rejectedReceipt in [false, true] {
        let fixture = try Fixture()
        let initial = try fixture.provider()
        _ = try await fixture.refresh(initial)

        let request = try fixture.action(
            rejectedReceipt ? "pause" : "start",
            revision: 1,
            deadline: fixture.clock.now().addingTimeInterval(5)
        )
        let original = try await fixture.send(request, initial)
        let bytes    = try #require(await fixture.storage.snapshot())
        fixture.clock.advance(10)  // A late retry cannot use the deadline to invent an outcome.

        let invalidRecords = [
            Data("malformed history".utf8),
            try changeRecord(bytes) { $0["schemaVersion"] = 2 },
            Data(repeating: 32, count: 16_385),
            try changeRecord(bytes) { $0["revision"] = 0 },
        ]
        for unusable in invalidRecords {
            try await assertUnusableHistoryPreservesUncertainty(
                fixture      : fixture,
                request      : request,
                original     : original,
                originalBytes: bytes,
                unusable     : unusable,
                diagnostic   : .corruptState
            )
        }
    }
}

@Test
func missingMismatchedAndIncompatibleHistoryCannotProveActionRejected() async throws {
    for rejectedReceipt in [false, true] {
        let fixture = try Fixture()
        let initial = try fixture.provider()
        _ = try await fixture.refresh(initial)

        let request  = try fixture.action(rejectedReceipt ? "pause" : "start", revision: 1)
        let original = try await fixture.send(request, initial)
        let bytes    = try #require(await fixture.storage.snapshot())
        fixture.clock.advance(10)

        // Use a fully valid record belonging to a different assignment, not a malformed identity.
        let other = try Fixture()
        _ = try await other.refresh(other.provider())

        let foreignBytes = try #require(await other.storage.snapshot())
        try await assertUnusableHistoryPreservesUncertainty(
            fixture      : fixture,
            request      : request,
            original     : original,
            originalBytes: bytes,
            unusable     : foreignBytes,
            diagnostic   : .assignmentMismatch
        )
        try await assertUnusableHistoryPreservesUncertainty(
            fixture      : fixture,
            request      : request,
            original     : original,
            originalBytes: bytes,
            unusable     : bytes,
            diagnostic   : .invalidConfiguration,
            duration     : 120
        )
        try await assertUnusableHistoryPreservesUncertainty(
            fixture      : fixture,
            request      : request,
            original     : original,
            originalBytes: bytes,
            unusable     : nil,
            diagnostic   : .missingState
        )
        try await assertUnusableHistoryPreservesUncertainty(
            fixture      : fixture,
            request      : request,
            original     : original,
            originalBytes: bytes,
            unusable     : bytes,
            diagnostic   : .assignmentMismatch,
            mode         : .freshAssignment
        )
    }
}

@Test
func nestedRejectedReceiptCorruptionLeavesOriginalOutcomeUnknownUntilRestored() async throws {
    let fixture = try Fixture()
    let initial = try fixture.provider()
    _ = try await fixture.refresh(initial)

    let request  = try fixture.action("pause", revision: 1)
    let original = try await fixture.send(request, initial)
    #expect(try isRejected(original))

    let bytes     = try #require(await fixture.storage.snapshot())
    let corrupted = try changeRecord(bytes) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        var outcome  = try #require(receipts[0]["outcome"] as? [String: Any])
        var rejected = try #require(outcome["rejected"] as? [String: Any])
        var reason   = try #require(rejected["reason"] as? [String: Any])

        reason["unexpected"]   = 1
        rejected["reason"]     = reason
        outcome["rejected"]    = rejected
        receipts[0]["outcome"] = outcome
        json["receipts"]       = receipts
    }
    try await assertUnusableHistoryPreservesUncertainty(
        fixture      : fixture,
        request      : request,
        original     : original,
        originalBytes: bytes,
        unusable     : corrupted,
        diagnostic   : .corruptState
    )
}
