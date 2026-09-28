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
    func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse {
        throw FocusError.invalidConfiguration
    }
    func subscribe(requirementID: String, grant: Grant) async throws -> UUID { throw FocusError.invalidConfiguration }
    func unsubscribe(subscriptionID: UUID) async throws { throw FocusError.invalidConfiguration }
}
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: Double) { lock.withLock { value.addTimeInterval(seconds) } }
}
private actor Storage: AddonStorageClient {
    enum Failure: Error { case lostReply }
    enum WriteMode { case normal, commitThenThrow, throwBeforeCommit }
    var data: Data?
    var writes = 0
    var reads = 0
    var mode = WriteMode.normal
    var failRead = false
    var gateRead = false
    var gateWrite = false
    var entered = false
    var waiter: CheckedContinuation<Void, Never>?
    func configure(_ mode: WriteMode = .normal, read: Bool = false, write: Bool = false) {
        self.mode = mode
        gateRead = read
        gateWrite = write
        entered = false
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
    func write(_ data: Data, key: String) async throws {
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
        gateRead = false
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
    let owner: AddonID
    let id: PublicationID
    let storage = Storage()
    let clock = Clock()
    init() throws {
        owner = try #require(AddonID(rawValue: "org.cascade.examples.focus"))
        id = PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID())
    }
    func provider(_ mode: FocusInitializationMode = .freshAssignment, duration: Double = 1500) throws
        -> StandaloneFocusProvider
    {
        try StandaloneFocusProvider(
            expectedOwner: owner,
            publicationID: id,
            mode: mode,
            duration: duration,
            clock: { clock.now() }
        )
    }
    func context() throws -> AddonContext {
        try AddonContext(services: UnusedServices(), storage: storage, generation: ConnectionGeneration(), grants: [])
    }
    func action(
        _ name: String,
        revision: UInt64,
        requestID: UUID = UUID(),
        input: Data = Data(),
        deadline: Date? = nil,
        publication: PublicationID? = nil
    ) throws -> ActionRequest {
        try ActionRequest(
            schemaVersion: 1,
            requestID: requestID,
            publicationID: publication ?? id,
            actionID: name,
            input: input,
            deadline: deadline ?? clock.now().addingTimeInterval(60),
            observedRevision: revision
        )
    }
    func refresh(_ p: StandaloneFocusProvider) async throws -> Publication {
        let o = try await p.handle(.refresh(id), context: context())
        return try #require(o.publications.first)
    }
    func send(_ r: ActionRequest, _ p: StandaloneFocusProvider) async throws -> ProviderOutput {
        let o = try await p.handle(.action(r), context: context())
        try o.validateContext(
            authenticatedAddonID: owner,
            expectedCompletion: .action(requestID: r.requestID),
            previousRevisions: [:]
        )
        #expect(o.checkpoint == nil)
        return o
    }
}
private func outcome(_ o: ProviderOutput) throws -> ActionOutcome {
    guard case .action(_, let value) = o.completion else { throw FocusError.corruptState }
    return value
}
private func isRejected(_ o: ProviderOutput) throws -> Bool {
    if case .rejected = try outcome(o) { return true }
    return false
}
private func revision(_ o: ProviderOutput) throws -> UInt64 { try #require(o.publications.first).revision }
private func nodes(_ p: Publication) -> [ContentNode] {
    func flatten(_ n: ContentNode) -> [ContentNode] { [n] + (n.children ?? []).flatMap(flatten) }
    return p.content?.widget.map { flatten($0.root) } ?? []
}
private func changeRecord(_ data: Data, _ change: (inout [String: Any]) throws -> Void) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try change(&json)
    return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
}

@Test func reducerFreezesRemainingAndDoesNotReviveOverdueTimer() throws {
    let now = Date(timeIntervalSince1970: 1000)
    var s = try FocusSession(duration: 120)
    try s.apply(.start, now: now)
    #expect(s.phase == .running)
    #expect(s.deadline == now.addingTimeInterval(120))
    try s.apply(.pause, now: now.addingTimeInterval(30))
    #expect(s.phase == .paused)
    #expect(s.remaining == 90)
    #expect(s.deadline == nil)
    try s.apply(.resume, now: now.addingTimeInterval(500))
    #expect(s.deadline == now.addingTimeInterval(590))
    try s.reconcile(now: now.addingTimeInterval(600))
    #expect(s.phase == .completed)
    #expect(s.remaining == 0)
    #expect(throws: (any Error).self) { try s.apply(.resume, now: now.addingTimeInterval(601)) }
    try s.apply(.end, now: now.addingTimeInterval(602))
    #expect(s.phase == .ended)
}
@Test func reducerClampsCivilClockRollbackAndRejectsInvalidDuration() throws {
    let now = Date(timeIntervalSince1970: 1000)
    var s = try FocusSession(duration: 120)
    try s.apply(.start, now: now)
    try s.apply(.pause, now: now.addingTimeInterval(-600))
    #expect(s.remaining == 120)
    for duration in [0.0, -1, Double.infinity, Double.nan, 86401] {
        #expect(throws: (any Error).self) { _ = try FocusSession(duration: duration) }
    }
}
@Test func providerLifecycleSurvivesRecreationAndGenerationChange() async throws {
    let f = try Fixture()
    let p = try f.provider()
    let initial = try await f.refresh(p)
    #expect(initial.id == f.id)
    #expect(initial.revision == 1)
    let start = try f.action("start", revision: 1)
    let a = try await f.send(start, p)
    #expect(try outcome(a) == .completed(payload: Data()))
    let running = try #require(a.publications.first)
    #expect(running.revision == 2)
    #expect(nodes(running).contains { $0.kind == .countdown && $0.deadline == f.clock.now().addingTimeInterval(1500) })
    #expect(running.expiresAt > f.clock.now().addingTimeInterval(1500))
    #expect(a.operations.count == 1)
    let wire = try JSONEncoder().encode(a)
    #expect(try ProviderOutput.decode(wire) == a)
    try a.validateContext(
        authenticatedAddonID: f.owner,
        expectedCompletion: .action(requestID: start.requestID),
        previousRevisions: [f.id: 1]
    )
    f.clock.advance(300)
    let recreated = try f.provider(.resumeExisting)
    let pause = try await f.send(f.action("pause", revision: 2), recreated)
    #expect(try revision(pause) == 3)
    #expect(pause.operations.isEmpty)
    #expect(nodes(try #require(pause.publications.first)).contains { $0.text == "20:00" })
    f.clock.advance(600)
    let resume = try await f.send(f.action("resume", revision: 3), recreated)
    #expect(
        nodes(try #require(resume.publications.first)).contains {
            $0.deadline == f.clock.now().addingTimeInterval(1200)
        }
    )
    #expect(resume.operations.count == 1)
    let end = try await f.send(f.action("end", revision: 4), recreated)
    #expect(try revision(end) == 5)
    #expect(end.operations.isEmpty)
    #expect(nodes(try #require(end.publications.first)).contains { $0.text == "Ended" })
}
@Test func configuredDurationAndNoOpStartDoNotExtendDeadline() async throws {
    let f = try Fixture()
    let p = try f.provider(duration: 60)
    _ = try await f.refresh(p)
    let first = try await f.send(f.action("start", revision: 1), p)
    f.clock.advance(10)
    let second = try await f.send(f.action("start", revision: 2), p)
    #expect(second.operations.isEmpty)
    #expect(
        nodes(try #require(first.publications.first)).filter { $0.kind == .countdown }.first?.deadline
            == nodes(try #require(second.publications.first)).filter { $0.kind == .countdown }.first?.deadline
    )
}
@Test func duplicateReceiptsPrecedeStaleFenceWithoutReplayingRevision() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let r = try f.action("start", revision: 1)
    _ = try await f.send(r, p)
    f.clock.advance(5)
    let p2 = try f.provider(.resumeExisting)
    let duplicate = try await f.send(r, p2)
    #expect(try outcome(duplicate) == .completed(payload: Data()))
    #expect(try revision(duplicate) == 3)
    #expect(duplicate.operations.isEmpty)
    let changed = try f.action("end", revision: 1, requestID: r.requestID, deadline: r.deadline)
    let before = await f.storage.snapshot()
    #expect(try isRejected(await f.send(changed, p2)))
    #expect(await f.storage.snapshot() == before)
    #expect(try isRejected(await f.send(f.action("pause", revision: 2), p2)))
}
@Test func rejectedInputsNeverMutateDurableState() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    let other = PublicationID(addonID: f.owner, instanceID: UUID(), sessionID: f.id.sessionID)
    let foreign = PublicationID(
        addonID: try #require(AddonID(rawValue: "other.owner")),
        instanceID: f.id.instanceID,
        sessionID: f.id.sessionID
    )
    let bad = [
        try f.action("reset", revision: 1), try f.action("start", revision: 1, input: Data([1])),
        try f.action("start", revision: 1, deadline: f.clock.now()), try f.action("start", revision: 0),
        try f.action("start", revision: 2), try f.action("start", revision: 1, publication: other),
        try f.action("start", revision: 1, publication: foreign),
    ]
    for r in bad {
        #expect(try isRejected(await f.send(r, p)))
        #expect(await f.storage.snapshot() == before)
    }
    await #expect(throws: (any Error).self) { _ = try await p.handle(.refresh(other), context: f.context()) }
    #expect(await f.storage.snapshot() == before)
}
@Test func missingResumeAndAssignmentMismatchPreserveState() async throws {
    let f = try Fixture()
    let resume = try f.provider(.resumeExisting)
    await #expect(throws: FocusError.missingState) { _ = try await f.refresh(resume) }
    let p = try f.provider()
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    let fresh = try f.provider()
    await #expect(throws: FocusError.assignmentMismatch) { _ = try await f.refresh(fresh) }
    let newID = PublicationID(addonID: f.owner, instanceID: f.id.instanceID, sessionID: UUID())
    let mismatch = try StandaloneFocusProvider(expectedOwner: f.owner, publicationID: newID, mode: .resumeExisting)
    await #expect(throws: FocusError.assignmentMismatch) {
        _ = try await mismatch.handle(.refresh(newID), context: f.context())
    }
    #expect(await f.storage.snapshot() == before)
    await f.storage.replace(nil)
    await #expect(throws: FocusError.missingState) { _ = try await f.refresh(p) }
}
@Test func boundedReceiptsEvictAndFenceOldRetry() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let first = try f.action("start", revision: 1)
    _ = try await f.send(first, p)
    for observed in 2...18 { _ = try await f.send(f.action("start", revision: UInt64(observed)), p) }
    let bytes = try #require(await f.storage.snapshot())
    #expect(bytes.count <= 16384)
    let record = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect((record["receipts"] as? [Any])?.count == 16)
    let resumed = try f.provider(.resumeExisting)
    #expect(try isRejected(await f.send(first, resumed)))
    #expect(await f.storage.snapshot() == bytes)
}
@Test func obsoleteAndEarlyExpiryCannotCompleteResumedTimer() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let started = try await f.send(f.action("start", revision: 1), p)
    guard case .schedule(_, let oldToken) = try #require(started.operations.first) else {
        throw FocusError.corruptState
    }
    f.clock.advance(5)
    _ = try await f.send(f.action("pause", revision: 2), p)
    let resumed = try await f.send(f.action("resume", revision: 3), p)
    guard case .schedule(_, let token) = try #require(resumed.operations.first) else { throw FocusError.corruptState }
    #expect(oldToken != token)
    let before = await f.storage.snapshot()
    for t in [oldToken, token] {
        let output = try await p.handle(.scheduled(eventID: t), context: f.context())
        #expect(output.publications.isEmpty)
        #expect(output.operations.isEmpty)
        #expect(await f.storage.snapshot() == before)
    }
    f.clock.advance(1500)
    let completed = try await p.handle(.scheduled(eventID: token), context: f.context())
    #expect(nodes(try #require(completed.publications.first)).contains { $0.text == "Completed" })
    #expect(completed.operations.isEmpty)
    let after = await f.storage.snapshot()
    let again = try await p.handle(.scheduled(eventID: token), context: f.context())
    #expect(again.publications.isEmpty)
    #expect(await f.storage.snapshot() == after)
}
@Test func overdueRefreshRepairsRefusedOutputAndResumeCannotReviveIt() async throws {
    let f = try Fixture()
    let p = try f.provider(duration: 10)
    _ = try await f.refresh(p)
    _ = try await f.send(f.action("start", revision: 1), p)  // Simulated discarded/refused output.
    f.clock.advance(20)
    let recreated = try f.provider(.resumeExisting, duration: 10)
    let repaired = try await f.refresh(recreated)
    #expect(repaired.revision == 3)
    #expect(nodes(repaired).contains { $0.text == "Completed" })
    let r = try await f.send(f.action("resume", revision: 3), recreated)
    #expect(try isRejected(r))
    #expect(r.operations.isEmpty)
}
@Test func uncertainCommittedWriteIsRereadBeforeRetryAndNeverReapplied() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    await f.storage.configure(.commitThenThrow)
    let r = try f.action("start", revision: 1)
    let unknown = try await f.send(r, p)
    #expect(try outcome(unknown) == .outcomeUnknown)
    #expect(unknown.publications.isEmpty)
    await f.storage.configure()
    let retry = try await f.send(r, p)
    #expect(try revision(retry) == 3)
    #expect(try outcome(retry) == .completed(payload: Data()))
    #expect(retry.operations.isEmpty)
    #expect((await f.storage.counts()).0 >= 3)
}
@Test func uncertainUncommittedWriteDoesNotAdvanceRevision() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    let r = try f.action("start", revision: 1)
    await f.storage.configure(.throwBeforeCommit)
    #expect(try outcome(await f.send(r, p)) == .outcomeUnknown)
    #expect(await f.storage.snapshot() == before)
    await f.storage.configure()
    let retry = try await f.send(r, p)
    #expect(try revision(retry) == 2)
    #expect(retry.operations.count == 1)
}
@Test func busyAcrossReadAndCancellationBeforeWriteHasNoEffect() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    await f.storage.configure(read: true)
    let r = try f.action("start", revision: 1)
    let task = Task { try await f.send(r, p) }
    try await f.storage.waitForEntry()
    await #expect(throws: FocusError.busy) { _ = try await f.refresh(p) }
    task.cancel()
    await f.storage.release()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await f.storage.snapshot() == before)
}
@Test func successfulWriteIsNotUndoneByCancellationAndBusySpansWrite() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    await f.storage.configure(write: true)
    let task = Task { try await f.send(f.action("start", revision: 1), p) }
    try await f.storage.waitForEntry()
    await #expect(throws: FocusError.busy) { _ = try await f.refresh(p) }
    task.cancel()
    await f.storage.release()
    let committed = try await task.value
    #expect(try outcome(committed) == .completed(payload: Data()))
    #expect(try revision(committed) == 2)
    #expect(try await f.refresh(f.provider(.resumeExisting)).revision == 3)
}
@Test func cancelledAmbiguousCommitStillReportsUnknown() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    await f.storage.configure(.commitThenThrow, write: true)
    let r = try f.action("start", revision: 1)
    let task = Task { try await f.send(r, p) }
    try await f.storage.waitForEntry()
    task.cancel()
    await f.storage.release()
    #expect(try outcome(await task.value) == .outcomeUnknown)
    await f.storage.configure()
    #expect(try revision(await f.send(r, f.provider(.resumeExisting))) == 3)
}
@Test func corruptFutureOversizedAndInconsistentRecordsAreNeverOverwritten() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let good = try #require(await f.storage.snapshot())
    let candidates = [
        Data("not json".utf8), Data(repeating: 32, count: 16385),
        try changeRecord(good) { $0["schemaVersion"] = 2 },
        try changeRecord(good) { $0["revision"] = -1 },
        try changeRecord(good) { $0["session"] = ["phase": "running", "duration": 1500, "remaining": 1500] },
        try changeRecord(good) { $0["receipts"] = Array(repeating: [:], count: 17) },
    ]
    for bytes in candidates {
        await f.storage.replace(bytes)
        let resumed = try f.provider(.resumeExisting)
        await #expect(throws: (any Error).self) { _ = try await f.refresh(resumed) }
        #expect(await f.storage.snapshot() == bytes)
    }
}
@Test func revisionExhaustionFailsBeforeStorageOrPublication() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let original = try #require(await f.storage.snapshot())
    let bytes = try changeRecord(original) { $0["revision"] = NSNumber(value: UInt64.max) }
    await f.storage.replace(bytes)
    let resumed = try f.provider(.resumeExisting)
    await #expect(throws: FocusError.revisionExhausted) { _ = try await f.refresh(resumed) }
    #expect(await f.storage.snapshot() == bytes)
}
@Test func stopIsEmptyWithoutFlushAndTerminatesAuthority() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    let stopped = try await p.handle(.stop(.permissionRevoked), context: f.context())
    #expect(
        stopped.publications.isEmpty && stopped.operations.isEmpty && stopped.completion == nil
            && stopped.checkpoint == nil
    )
    #expect(await f.storage.snapshot() == before)
    await #expect(throws: FocusError.stopped) { _ = try await f.refresh(p) }
}
@Test func sourceManifestMatchesImplementedPublicBoundary() throws {
    let url = try #require(Bundle.module.url(forResource: "Manifest", withExtension: "json"))
    let m = try AddonManifest.decode(Data(contentsOf: url))
    #expect(m.sourceApp == nil && m.requires.isEmpty && m.provides.isEmpty && m.bundledLibraries.isEmpty)
    #expect(m.features.flatMap { $0.actions ?? [] } == ["start", "pause", "resume", "end"])
    #expect(m.permissions.map(\.id) == [.storageOwn])
    #expect(m.resources.background == .scheduledDeadline)
}

@Test func overdueStateIsReconciledUsingClockAfterStorageAwait() async throws {
    let f = try Fixture()
    let p = try f.provider(duration: 10)
    _ = try await f.refresh(p)
    _ = try await f.send(f.action("start", revision: 1), p)
    await f.storage.configure(read: true)
    let task = Task { try await f.send(f.action("pause", revision: 2), p) }
    try await f.storage.waitForEntry()
    f.clock.advance(20)
    await f.storage.release()
    let result = try await task.value
    #expect(try isRejected(result))
    #expect(nodes(try #require(result.publications.first)).contains { $0.text == "Completed" })
    #expect(result.operations.isEmpty)
}
@Test func deadlineExpiringDuringReadPreventsStorageHandoff() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    let counts = await f.storage.counts()
    let r = try f.action("start", revision: 1, deadline: f.clock.now().addingTimeInterval(5))
    await f.storage.configure(read: true)
    let task = Task { try await f.send(r, p) }
    try await f.storage.waitForEntry()
    f.clock.advance(10)
    await f.storage.release()
    #expect(try isRejected(await task.value))
    #expect(await f.storage.snapshot() == before)
    #expect((await f.storage.counts()).1 == counts.1)
}
@Test func unknownPersistedFieldsAndAssignmentPayloadAreCorruption() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    _ = try await f.send(f.action("start", revision: 1), p)
    let original = try #require(await f.storage.snapshot())
    let extraReceipt = try changeRecord(original) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        receipts[0]["unexpected"] = 1
        json["receipts"] = receipts
    }
    let extraAssignment = try changeRecord(original) { json in
        var assignment = try #require(json["assignment"] as? [String: Any])
        assignment["unexpected"] = 1
        json["assignment"] = assignment
    }
    let extraRequest = try changeRecord(original) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        var request = try #require(receipts[0]["request"] as? [String: Any])
        var assignment = try #require(request["publicationID"] as? [String: Any])
        assignment["unexpected"] = 1
        request["publicationID"] = assignment
        receipts[0]["request"] = request
        json["receipts"] = receipts
    }
    for data in [extraReceipt, extraAssignment, extraRequest] {
        await f.storage.replace(data)
        let resumed = try f.provider(.resumeExisting)
        await #expect(throws: FocusError.corruptState) { _ = try await f.refresh(resumed) }
        #expect(await f.storage.snapshot() == data)
    }
}
@Test func failedRereadAfterUncertainWriteBlocksMutationUntilAuthoritativeRead() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let r = try f.action("start", revision: 1)
    await f.storage.configure(.commitThenThrow)
    #expect(try outcome(await f.send(r, p)) == .outcomeUnknown)
    let committed = await f.storage.snapshot()
    let counts = await f.storage.counts()
    await f.storage.configure()
    await f.storage.setReadFailure(true)
    let unreadable = try await f.send(r, p)
    #expect(try outcome(unreadable) == .outcomeUnknown)
    #expect(unreadable.publications.isEmpty && unreadable.operations.isEmpty && unreadable.checkpoint == nil)
    #expect(await f.storage.snapshot() == committed)
    #expect((await f.storage.counts()).1 == counts.1)
    await f.storage.setReadFailure(false)
    #expect(try revision(await f.send(r, p)) == 3)
}
@Test func uncertainRefreshReservesGapAndMissingStateStillFailsClosed() async throws {
    let f = try Fixture()
    let p = try f.provider()
    await f.storage.configure(.commitThenThrow)
    await #expect(throws: (any Error).self) { _ = try await f.refresh(p) }
    await f.storage.configure()
    #expect(try await f.refresh(p).revision == 2)
    await f.storage.replace(nil)
    await #expect(throws: FocusError.missingState) { _ = try await f.refresh(p) }
}
@Test func changedFingerprintDeadlineAndRevisionCannotReuseReceipt() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let r = try f.action("start", revision: 1)
    _ = try await f.send(r, p)
    let before = await f.storage.snapshot()
    for changed in [
        try f.action("start", revision: 2, requestID: r.requestID, deadline: r.deadline),
        try f.action("start", revision: 1, requestID: r.requestID, deadline: r.deadline.addingTimeInterval(1)),
    ] {
        #expect(try isRejected(await f.send(changed, p)))
        #expect(await f.storage.snapshot() == before)
    }
}
@Test func configurationMismatchAndInvalidClockNeverWrite() async throws {
    let f = try Fixture()
    let p = try f.provider(duration: 60)
    _ = try await f.refresh(p)
    let before = await f.storage.snapshot()
    let wrong = try f.provider(.resumeExisting, duration: 120)
    await #expect(throws: FocusError.invalidConfiguration) { _ = try await f.refresh(wrong) }
    let badClock = try StandaloneFocusProvider(
        expectedOwner: f.owner,
        publicationID: f.id,
        mode: .resumeExisting,
        duration: 60,
        clock: { Date(timeIntervalSince1970: .infinity) }
    )
    await #expect(throws: FocusError.invalidConfiguration) { _ = try await f.refresh(badClock) }
    #expect(await f.storage.snapshot() == before)
}
@Test func overduePauseRejectionReceiptIsStableAcrossRecreation() async throws {
    let f = try Fixture()
    let p = try f.provider(duration: 10)
    _ = try await f.refresh(p)
    _ = try await f.send(f.action("start", revision: 1), p)
    f.clock.advance(20)
    let pause = try f.action("pause", revision: 2)
    let refused = try await f.send(pause, p)
    #expect(try isRejected(refused))
    #expect(nodes(try #require(refused.publications.first)).contains { $0.text == "Completed" })
    let duplicate = try await f.send(pause, f.provider(.resumeExisting, duration: 10))
    #expect(try outcome(duplicate) == outcome(refused))
    #expect(try revision(duplicate) == 4)
    #expect(duplicate.operations.isEmpty)
}

// A controlled pair of reads demonstrates the public storage API's lack of CAS.
private actor CompetingStorage: AddonStorageClient {
    var data: Data
    var reads: [CheckedContinuation<Data?, any Error>] = []
    init(_ data: Data) { self.data = data }
    func read(key: String) async throws -> Data? {
        #expect(key == StandaloneFocusProvider.storageKey)
        return try await withCheckedThrowingContinuation { continuation in
            reads.append(continuation)
            if reads.count == 2 {
                let snapshot = data
                for r in reads { r.resume(returning: snapshot) }
                reads.removeAll()
            }
        }
    }
    func write(_ data: Data, key: String) async throws {
        #expect(data.count <= 16_384)
        self.data = data
    }
    func remove(key: String) async throws { Issue.record("Unexpected remove") }
}
@Test func competingProvidersRequireHostSerializationRatherThanClaimingCAS() async throws {
    let f = try Fixture()
    _ = try await f.refresh(f.provider())
    let shared = CompetingStorage(try #require(await f.storage.snapshot()))
    let context = try AddonContext(
        services: UnusedServices(),
        storage: shared,
        generation: ConnectionGeneration(),
        grants: []
    )
    let p1 = try f.provider(.resumeExisting)
    let p2 = try f.provider(.resumeExisting)
    let start = try f.action("start", revision: 1)
    let end = try f.action("end", revision: 1)
    async let left = p1.handle(.action(start), context: context)
    async let right = p2.handle(.action(end), context: context)
    let (a, b) = try await (left, right)
    #expect(try revision(a) == 2)
    #expect(try revision(b) == 2)
    #expect(try outcome(a) == .completed(payload: Data()))
    #expect(try outcome(b) == .completed(payload: Data()))
    #expect(throws: (any Error).self) {
        try b.validateContext(
            authenticatedAddonID: f.owner,
            expectedCompletion: .action(requestID: end.requestID),
            previousRevisions: [f.id: 2]
        )
    }
}
@Test func malformedReceiptsAndPhaseTokenMismatchPreserveBytes() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    _ = try await f.send(f.action("start", revision: 1), p)
    let good = try #require(await f.storage.snapshot())
    let badToken = try changeRecord(good) { $0["activeToken"] = "unknown" }
    let missingToken = try changeRecord(good) { $0.removeValue(forKey: "activeToken") }
    let badRemaining = try changeRecord(good) { json in
        var session = try #require(json["session"] as? [String: Any])
        session["remaining"] = -1
        json["session"] = session
    }
    let tooNewReceipt = try changeRecord(good) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        receipts[0]["revision"] = 3
        json["receipts"] = receipts
    }
    let duplicateReceipt = try changeRecord(good) { json in
        let receipts = try #require(json["receipts"] as? [[String: Any]])
        json["receipts"] = receipts + receipts
    }
    let nonemptyInput = try changeRecord(good) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        var request = try #require(receipts[0]["request"] as? [String: Any])
        request["input"] = "AQ=="
        receipts[0]["request"] = request
        json["receipts"] = receipts
    }
    let unknownOutcome = try changeRecord(good) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        receipts[0]["outcome"] = ["outcomeUnknown": [:]]
        json["receipts"] = receipts
    }
    for bytes in [badToken, missingToken, badRemaining, tooNewReceipt, duplicateReceipt, nonemptyInput, unknownOutcome]
    {
        await f.storage.replace(bytes)
        await #expect(throws: FocusError.corruptState) { _ = try await f.refresh(f.provider(.resumeExisting)) }
        #expect(await f.storage.snapshot() == bytes)
    }
}
@Test func refreshesReserveRevisionsWithoutDuplicatingScheduleWork() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    _ = try await f.send(f.action("start", revision: 1), p)
    for wanted in 3...5 {
        let output = try await p.handle(.refresh(f.id), context: f.context())
        #expect(try revision(output) == UInt64(wanted))
        #expect(output.operations.isEmpty)
        try output.validateContext(
            authenticatedAddonID: f.owner,
            expectedCompletion: nil,
            previousRevisions: [f.id: UInt64(wanted - 1)]
        )
    }
    #expect(try isRejected(await f.send(f.action("pause", revision: 2), p)))
}

@Test func retainedCommittedReceiptOutlivesDeadlineWithoutReapplyingCommand() async throws {
    let f = try Fixture()
    let p = try f.provider()
    _ = try await f.refresh(p)
    let r = try f.action("start", revision: 1, deadline: f.clock.now().addingTimeInterval(5))
    let original = try await f.send(r, p)
    let originalDeadline = nodes(try #require(original.publications.first)).first { $0.kind == .countdown }?.deadline
    f.clock.advance(10)
    let recreated = try f.provider(.resumeExisting)
    let late = try await f.send(r, recreated)
    #expect(try outcome(late) == .completed(payload: Data()))
    #expect(try revision(late) == 3)
    #expect(late.operations.isEmpty)
    #expect(nodes(try #require(late.publications.first)).first { $0.kind == .countdown }?.deadline == originalDeadline)
    let before = await f.storage.snapshot()
    let changed = try f.action("end", revision: 1, requestID: r.requestID, deadline: r.deadline)
    #expect(try isRejected(await f.send(changed, recreated)))
    #expect(await f.storage.snapshot() == before)
    f.clock.advance(2000)
    let overdue = try await f.send(r, recreated)
    #expect(try outcome(overdue) == .completed(payload: Data()))
    #expect(try revision(overdue) == 4)
    #expect(nodes(try #require(overdue.publications.first)).contains { $0.text == "Completed" })
    #expect(overdue.operations.isEmpty)
}

@Test func recreatedProviderReadFailureCannotRejectKnownOrPotentiallyCommittedAction() async throws {
    for rejectedReceipt in [false, true] {
        let f = try Fixture()
        let initial = try f.provider()
        _ = try await f.refresh(initial)
        let request = try f.action(
            rejectedReceipt ? "pause" : "start",
            revision: 1,
            deadline: f.clock.now().addingTimeInterval(5)
        )
        let committed = try await f.send(request, initial)  // Output could be lost after the known commit.
        let originalOutcome = try outcome(committed)
        let bytes = await f.storage.snapshot()
        let before = await f.storage.counts()
        f.clock.advance(10)
        let recreated = try f.provider(.resumeExisting)
        await f.storage.setReadFailure(true)
        let unreadable = try await f.send(request, recreated)
        #expect(try outcome(unreadable) == .outcomeUnknown)
        #expect(unreadable.publications.isEmpty && unreadable.operations.isEmpty && unreadable.checkpoint == nil)
        #expect(await f.storage.snapshot() == bytes)
        #expect((await f.storage.counts()).1 == before.1)
        // Even a different valid intent cannot prove absence of its own receipt while reads fail.
        let unobserved = try f.action("end", revision: 2)
        #expect(try outcome(await f.send(unobserved, recreated)) == .outcomeUnknown)
        // Proven invalid input still refuses before lookup.
        #expect(try isRejected(await f.send(f.action("reset", revision: 2), recreated)))
        #expect((await f.storage.counts()).1 == before.1)
        await f.storage.setReadFailure(false)
        let recovered = try await f.send(request, recreated)
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

@Test func nestedUnknownRejectedFailureKeysRefusePublicResumeWithoutOverwriting() async throws {
    let f = try Fixture()
    let provider = try f.provider()
    _ = try await f.refresh(provider)
    let request = try f.action("pause", revision: 1)
    let refused = try await f.send(request, provider)
    #expect(try isRejected(refused))
    let original = try #require(await f.storage.snapshot())
    let corrupt = try changeRecord(original) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        var actionOutcome = try #require(receipts[0]["outcome"] as? [String: Any])
        var rejected = try #require(actionOutcome["rejected"] as? [String: Any])
        var reason = try #require(rejected["reason"] as? [String: Any])
        reason["unexpected"] = 1
        rejected["reason"] = reason
        actionOutcome["rejected"] = rejected
        receipts[0]["outcome"] = actionOutcome
        json["receipts"] = receipts
    }
    await f.storage.replace(corrupt)
    let before = await f.storage.counts()
    let resumed = try f.provider(.resumeExisting)
    await #expect(throws: FocusError.corruptState) { _ = try await f.refresh(resumed) }
    #expect(await f.storage.snapshot() == corrupt)
    #expect((await f.storage.counts()).1 == before.1)
}

@Test func recoveredReceiptRemainsKnownAcrossAmbiguousSnapshotWrites() async throws {
    // 16 cases: completed/rejected x uncommitted/committed x late/overdue x cancellation/no cancellation.
    for rejectedReceipt in [false, true] {
        for commitsSnapshot in [false, true] {
            for overdue in [false, true] {
                for cancelled in [false, true] {
                    let f = try Fixture()
                    let initial = try f.provider()
                    _ = try await f.refresh(initial)
                    let request = try f.action(
                        rejectedReceipt ? "pause" : "start",
                        revision: 1,
                        deadline: f.clock.now().addingTimeInterval(5)
                    )
                    let original = try await f.send(request, initial)
                    let known: ActionOutcome =
                        rejectedReceipt
                        ? .rejected(
                            reason: AddonFailure(code: .invalidPayload, reason: "Command unavailable in current phase")
                        )
                        : .completed(payload: Data())
                    #expect(try outcome(original) == known)
                    // Give both original receipt kinds an active timer whose reconciliation can be uncertain.
                    if rejectedReceipt { _ = try await f.send(f.action("start", revision: 2), initial) }
                    let highWater: UInt64 = rejectedReceipt ? 3 : 2
                    let beforeBytes = try #require(await f.storage.snapshot())
                    let beforeJSON = try #require(JSONSerialization.jsonObject(with: beforeBytes) as? [String: Any])
                    let beforeSession = try #require(beforeJSON["session"] as? [String: Any])
                    let timerID = try #require(beforeSession["timerID"] as? String)
                    f.clock.advance(overdue ? 1600 : 10)
                    let recreated = try f.provider(.resumeExisting)
                    await f.storage.configure(commitsSnapshot ? .commitThenThrow : .throwBeforeCommit, write: cancelled)
                    let duplicate = Task { try await f.send(request, recreated) }
                    if cancelled {
                        try await f.storage.waitForEntry()
                        duplicate.cancel()
                        await f.storage.release()
                    }
                    let result = try await duplicate.value
                    #expect(result.completion == .action(requestID: request.requestID, outcome: known))
                    #expect(result.publications.isEmpty && result.operations.isEmpty && result.checkpoint == nil)
                    let afterBytes = try #require(await f.storage.snapshot())
                    if !commitsSnapshot { #expect(afterBytes == beforeBytes) }
                    let afterJSON = try #require(JSONSerialization.jsonObject(with: afterBytes) as? [String: Any])
                    let session = try #require(afterJSON["session"] as? [String: Any])
                    #expect(session["timerID"] as? String == timerID)
                    #expect(session["phase"] as? String == (commitsSnapshot && overdue ? "completed" : "running"))
                    let attempts = await f.storage.counts()
                    // A recovered receipt still rejects a changed fingerprint; no new write is attempted.
                    let changed = try f.action(
                        "end",
                        revision: 1,
                        requestID: request.requestID,
                        deadline: request.deadline
                    )
                    #expect(try isRejected(await f.send(changed, recreated)))
                    #expect((await f.storage.counts()).1 == attempts.1)
                    #expect(await f.storage.snapshot() == afterBytes)
                    await f.storage.configure()
                    let beforeRefresh = await f.storage.counts()
                    let repaired = try await recreated.handle(.refresh(f.id), context: f.context())
                    #expect((await f.storage.counts()).0 == beforeRefresh.0 + 1)
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
                    let retry = try await f.send(request, recreated)
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
    fixture: Fixture,
    request: ActionRequest,
    original: ProviderOutput,
    originalBytes: Data,
    unusable: Data?,
    diagnostic: FocusError,
    mode: FocusInitializationMode = .resumeExisting,
    duration: Double = 1500
) async throws {
    await fixture.storage.replace(unusable)
    let provider = try fixture.provider(mode, duration: duration)
    let before = await fixture.storage.counts()
    let unknown = try await fixture.send(request, provider)
    #expect(unknown.completion == .action(requestID: request.requestID, outcome: .outcomeUnknown))
    #expect(unknown.publications.isEmpty && unknown.operations.isEmpty && unknown.checkpoint == nil)
    #expect(await fixture.storage.snapshot() == unusable)
    #expect((await fixture.storage.counts()).1 == before.1)
    await #expect(throws: diagnostic) { _ = try await fixture.refresh(provider) }
    #expect(await fixture.storage.snapshot() == unusable)
    #expect((await fixture.storage.counts()).1 == before.1)
    // Request validation remains independent of the unusable ledger.
    #expect(try isRejected(await fixture.send(fixture.action("reset", revision: 2), provider)))
    let foreign = PublicationID(addonID: fixture.owner, instanceID: UUID(), sessionID: fixture.id.sessionID)
    #expect(try isRejected(await fixture.send(fixture.action("start", revision: 2, publication: foreign), provider)))
    #expect((await fixture.storage.counts()).0 == before.0 + 2)
    #expect((await fixture.storage.counts()).1 == before.1)

    // Only an external restoration repairs the ledger; the provider never repairs it itself.
    await fixture.storage.replace(originalBytes)
    let recovered = try await fixture.send(request, fixture.provider(.resumeExisting))
    #expect(try outcome(recovered) == outcome(original))
    #expect(try revision(recovered) == 3)
    #expect(recovered.operations.isEmpty)
    let originalRecord = try #require(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
    let recoveredBytes = try #require(await fixture.storage.snapshot())
    let recoveredRecord = try #require(JSONSerialization.jsonObject(with: recoveredBytes) as? [String: Any])
    let originalSession = try #require(originalRecord["session"] as? NSDictionary)
    let recoveredSession = try #require(recoveredRecord["session"] as? NSDictionary)
    #expect(originalSession == recoveredSession)  // No restart, new timer ID, deadline extension or phase command replay.
}

@Test func malformedUnsupportedAndInvalidHistoryLeaveCommittedActionUnknown() async throws {
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
        let bytes = try #require(await fixture.storage.snapshot())
        fixture.clock.advance(10)  // A late retry cannot use the deadline to invent an outcome.
        let invalidRecords = [
            Data("malformed history".utf8),
            try changeRecord(bytes) { $0["schemaVersion"] = 2 },
            Data(repeating: 32, count: 16_385),
            try changeRecord(bytes) { $0["revision"] = 0 },
        ]
        for unusable in invalidRecords {
            try await assertUnusableHistoryPreservesUncertainty(
                fixture: fixture,
                request: request,
                original: original,
                originalBytes: bytes,
                unusable: unusable,
                diagnostic: .corruptState
            )
        }
    }
}

@Test func missingMismatchedAndIncompatibleHistoryCannotProveActionRejected() async throws {
    for rejectedReceipt in [false, true] {
        let fixture = try Fixture()
        let initial = try fixture.provider()
        _ = try await fixture.refresh(initial)
        let request = try fixture.action(rejectedReceipt ? "pause" : "start", revision: 1)
        let original = try await fixture.send(request, initial)
        let bytes = try #require(await fixture.storage.snapshot())
        fixture.clock.advance(10)
        // Use a fully valid record belonging to a different assignment, not a malformed identity.
        let other = try Fixture()
        _ = try await other.refresh(other.provider())
        let foreignBytes = try #require(await other.storage.snapshot())
        try await assertUnusableHistoryPreservesUncertainty(
            fixture: fixture,
            request: request,
            original: original,
            originalBytes: bytes,
            unusable: foreignBytes,
            diagnostic: .assignmentMismatch
        )
        try await assertUnusableHistoryPreservesUncertainty(
            fixture: fixture,
            request: request,
            original: original,
            originalBytes: bytes,
            unusable: bytes,
            diagnostic: .invalidConfiguration,
            duration: 120
        )
        try await assertUnusableHistoryPreservesUncertainty(
            fixture: fixture,
            request: request,
            original: original,
            originalBytes: bytes,
            unusable: nil,
            diagnostic: .missingState
        )
        try await assertUnusableHistoryPreservesUncertainty(
            fixture: fixture,
            request: request,
            original: original,
            originalBytes: bytes,
            unusable: bytes,
            diagnostic: .assignmentMismatch,
            mode: .freshAssignment
        )
    }
}

@Test func nestedRejectedReceiptCorruptionLeavesOriginalOutcomeUnknownUntilRestored() async throws {
    let fixture = try Fixture()
    let initial = try fixture.provider()
    _ = try await fixture.refresh(initial)
    let request = try fixture.action("pause", revision: 1)
    let original = try await fixture.send(request, initial)
    #expect(try isRejected(original))
    let bytes = try #require(await fixture.storage.snapshot())
    let corrupted = try changeRecord(bytes) { json in
        var receipts = try #require(json["receipts"] as? [[String: Any]])
        var outcome = try #require(receipts[0]["outcome"] as? [String: Any])
        var rejected = try #require(outcome["rejected"] as? [String: Any])
        var reason = try #require(rejected["reason"] as? [String: Any])
        reason["unexpected"] = 1
        rejected["reason"] = reason
        outcome["rejected"] = rejected
        receipts[0]["outcome"] = outcome
        json["receipts"] = receipts
    }
    try await assertUnusableHistoryPreservesUncertainty(
        fixture: fixture,
        request: request,
        original: original,
        originalBytes: bytes,
        unusable: corrupted,
        diagnostic: .corruptState
    )
}
