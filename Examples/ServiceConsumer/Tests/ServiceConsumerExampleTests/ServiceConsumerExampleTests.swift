//
//  ServiceConsumerExampleTests.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract

@Test
func strictCodecSuccess() throws {
    #expect(try FocusSessionsContract.decode(Data(#"{"schemaVersion":1,"completedSessions":3}"#.utf8)) == 3)
}

@Test
func strictCodecRejects() {
    for value in [
        #"{"schemaVersion":1,"completedSessions":true}"#,
        #"{"schemaVersion":1,"completedSessions":3,"extra":0}"#,
        #"{"schemaVersion":2,"completedSessions":3}"#,
        #"{"schemaVersion":1,"completedSessions":1001}"#,
        #"{"schemaVersion":1,"completedSessions":-1}"#,
        #"{"schemaVersion":1,"completedSessions":3.5}"#,
        #"{"schemaVersion":1,"completedSessions":3,"completedSessions":4}"#,
        "{}",
        String(repeating: "x", count: 257)
    ] {
        #expect(throws: (any Error).self) { try FocusSessionsContract.decode(Data(value.utf8)) }
    }
}

import FocusSessionsExampleProvider
import ServiceConsumerProvider

@Test
func presentPairAndFinitePublication() async throws {
    let client      = RecordingClient()
    let issuedGrant = try grant(expiry: instant.addingTimeInterval(1))

    let provider = try ServiceConsumerProvider(
        owner     : owner,
        assignment: assignment,
        clock     : { instant }
    )
    let addonContext = try context(client, [issuedGrant])
    let output       = try await provider.handle(.refresh(assignment), context: addonContext)
    #expect(output.completion == nil && output.operations.isEmpty && output.checkpoint == nil)

    let publication = try #require(output.publications.first)
    #expect(output.publications.count == 1 && publication.id == assignment && publication.revision == 1)
    #expect(
        publication.expiresAt == instant.addingTimeInterval(30)
            && publication.stalePolicy == .remove
            && publication.timeline == nil
    )
    #expect(publication.content?.widget?.root.text == "Example completed sessions: 3")
    #expect(publication.content?.widget?.privacy == .publicContent)
    try output.validateContext(
        authenticatedAddonID: owner,
        expectedCompletion  : nil,
        previousRevisions   : [:]
    )

    let calls = await client.calls
    let call  = try #require(calls.first)
    #expect(calls.count == 1 && call.1 == issuedGrant && call.0.schemaVersion == 1 && call.0.payload.isEmpty)
    #expect(
        call.0.contractID == "com.example.focus.sessions"
            && call.0.operation == "read"
            && call.0.deadline == issuedGrant.expiresAt
    )

    let second = try await provider.handle(.refresh(assignment), context: addonContext)
    #expect(second.publications.first?.revision == 2)

    let again = await client.calls
    #expect(again[0].0.requestID != again[1].0.requestID)
}

@Test
func noUsableGrantRequestsOnce() async throws {
    let wrongOwner = AddonID(rawValue: "com.example.other")!

    for grants in [
        [],
        [try grant(owner: wrongOwner)],
        [try grant(service: "other.service")],
        [try grant(feature: "other")],
        [try grant(operation: "write")],
        [try grant(expiry: instant)]
    ] {
        let client   = RecordingClient()
        let provider = try ServiceConsumerProvider(
            owner     : owner,
            assignment: assignment,
            clock     : { instant }
        )

        let output = try await provider.handle(.refresh(assignment), context: context(client, grants))
        #expect(output.operations == [
            .requestService(
                requirementID: "com.example.focus.sessions",
                scope        : try ServiceScope(featureID: "summary", operation: "read")
            )
        ])
        #expect(output.publications.isEmpty && output.completion == nil)
        #expect(await client.count() == 0)
    }
}

@Test
func ambiguityAndExactAssignmentRejectBeforeInvoke() async throws {
    let client   = RecordingClient()
    let provider = try ServiceConsumerProvider(
        owner     : owner,
        assignment: assignment,
        clock     : { instant }
    )
    await #expect(throws: (any Error).self) {
        try await provider.handle(.refresh(assignment), context: context(client, [grant(), grant()]))
    }

    let other = PublicationID(
        addonID   : owner,
        instanceID: assignment.instanceID,
        sessionID : UUID()
    )
    await #expect(throws: (any Error).self) {
        try await provider.handle(.refresh(other), context: context(client, [grant()]))
    }
    #expect(await client.count() == 0)
    #expect(throws: (any Error).self) {
        try ServiceConsumerProvider(
            owner     : AddonID(rawValue: "com.example.other")!,
            assignment: assignment,
            clock     : { instant }
        )
    }
    #expect(throws: (any Error).self) { try context(client, [grant(gen: ConnectionGeneration())]) }
}

@Test
func scriptedFailuresAreUnchangedOutcomesOnly() async throws {
    for code in [
        AddonFailure.Code.permissionDenied,
        .sessionRevoked,
        .versionConflict,
        .dependencyUnavailable,
        .deadlineExceeded,
        .outcomeUnknown
    ] {
        let failure  = AddonFailure(code: code, reason: "Scripted client outcome")
        let client   = RecordingClient(failure: failure)
        let provider = try ServiceConsumerProvider(
            owner     : owner,
            assignment: assignment,
            clock     : { instant }
        )
        await #expect(throws: failure) {
            try await provider.handle(.refresh(assignment), context: context(client, [grant()]))
        }
        #expect(await client.count() == 1)
    }
}

@Test
func responseIdentityAndPayloadRejected() async throws {
    for response in [
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : "other.service",
            operation    : "read",
            payload      : Data()
        ),
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "write",
            payload      : Data()
        ),
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data("{}".utf8)
        )
    ] {
        let client   = RecordingClient(response: response)
        let provider = try ServiceConsumerProvider(
            owner     : owner,
            assignment: assignment,
            clock     : { instant }
        )
        await #expect(throws: (any Error).self) {
            try await provider.handle(.refresh(assignment), context: context(client, [grant()]))
        }
        #expect(await client.count() == 1)
    }
}

@Test
func busyStopAndCancellationDiscardLateResults() async throws {
    for stop in [false, true] {
        let client   = RecordingClient(suspended: true)
        let provider = try ServiceConsumerProvider(
            owner     : owner,
            assignment: assignment,
            clock     : { instant }
        )
        let addonContext = try context(client, [grant()])

        try await withObservedRefresh(client: client, operation: {
            try await provider.handle(.refresh(assignment), context: addonContext)
        }) { signal, task in
            try requireInvocation(signal)
            await expectFailureCode(.rateLimited) {
                try await provider.handle(.refresh(assignment), context: addonContext)
            }

            let unrelated = try await provider.handle(.scheduled(eventID: "ignored"), context: addonContext)
            #expect(unrelated.publications.isEmpty)
            if stop {
                let output = try await provider.handle(.stop(.hostStopping), context: addonContext)
                #expect(output.publications.isEmpty)
            } else {
                task.cancel()
            }

            await client.release()
            if stop {
                await expectFailureCode(.sessionRevoked) { try await task.value }
            } else {
                await #expect(throws: CancellationError.self) { try await task.value }
            }

            #expect(await client.count() == 1)
            if stop {
                await expectFailureCode(.sessionRevoked) {
                    try await provider.handle(.refresh(assignment), context: addonContext)
                }
            }
        }
        #expect(await !client.hasHeldWork())
    }
}

@Test
func providerValidationAndCorrelation() async throws {
    let provider     = FocusSessionsExampleProvider(clock: { instant })
    let client       = RecordingClient()
    let addonContext = try context(client, [])

    for request in [
        try invocation(contract: "other.service"),
        try invocation(operation: "write"),
        try invocation(payload: Data([0])),
        try invocation(deadline: instant)
    ] {
        await #expect(throws: (any Error).self) {
            try await provider.handle(.serviceRequest(request), context: addonContext)
        }
    }

    let request    = try invocation()
    let output     = try await provider.handle(.serviceRequest(request), context: addonContext)
    let decoded    = try ProviderOutput.decode(JSONEncoder().encode(output))
    let completion = try #require(decoded.completion)
    try completion.validateCorrelation(
        .service(
            requestID : request.requestID,
            contractID: request.contractID,
            operation : request.operation
        )
    )

    for expected in [
        CompletionExpectation.service(
            requestID : UUID(),
            contractID: request.contractID,
            operation : request.operation
        ),
        .service(
            requestID : request.requestID,
            contractID: "other.service",
            operation : request.operation
        ),
        .service(
            requestID : request.requestID,
            contractID: request.contractID,
            operation : "write"
        )
    ] {
        #expect(throws: (any Error).self) { try completion.validateCorrelation(expected) }
    }

    let stopped = try await provider.handle(.stop(.idle), context: addonContext)
    #expect(stopped.completion == nil)
    await #expect(throws: (any Error).self) {
        try await provider.handle(.serviceRequest(request), context: addonContext)
    }
}

@Test
func manifestDeclarationsDoNotResolveVersions() throws {
    let directory = try #require(Bundle.module.url(forResource: "Manifests", withExtension: nil))
    let consumer  = try JSONDecoder().decode(
        AddonManifest.self,
        from: Data(contentsOf: directory.appendingPathComponent("Consumer.json"))
    )

    let bytes    = try Data(contentsOf: directory.appendingPathComponent("Provider.json"))
    let provider = try JSONDecoder().decode(AddonManifest.self, from: bytes)
    #expect(
        consumer.requires.first?.version == ">=1.0.0 <2.0.0"
            && consumer.requires.first?.id == "com.example.focus.sessions"
    )
    #expect(consumer.provides.isEmpty && provider.requires.isEmpty && provider.provides.first?.version == "1.0.0")

    let incompatibleBytes = Data(
        String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\"1.0.0\"", with: "\"2.0.0\"")
            .utf8
    )
    let incompatible = try JSONDecoder().decode(AddonManifest.self, from: incompatibleBytes)
    #expect(incompatible.provides.first?.version == "2.0.0") // declaration fixture, no resolver
}

@Test
func controlledLateCivilResponseIsRejected() async throws {
    let clock  = CivilClock()
    let client = RecordingClient(suspended: true)

    let provider = try ServiceConsumerProvider(
        owner     : owner,
        assignment: assignment,
        clock     : { clock.now() }
    )
    let addonContext = try context(client, [grant(expiry: instant.addingTimeInterval(1))])

    try await withObservedRefresh(client: client, operation: {
        try await provider.handle(.refresh(assignment), context: addonContext)
    }) { signal, task in
        try requireInvocation(signal)
        clock.advance(to: instant.addingTimeInterval(1))
        await client.release()
        await expectFailureCode(.deadlineExceeded) { try await task.value }
    }
    #expect(await !client.hasHeldWork())
    #expect(await client.count() == 1)

    clock.advance(to: instant)
    let fresh  = RecordingClient()
    let output = try await provider.handle(.refresh(assignment), context: context(fresh, [grant()]))
    #expect(output.publications.first?.revision == 1)
    #expect(await fresh.calls.first?.0.deadline == instant.addingTimeInterval(2))
}

@Test
func codecAcceptsBoundaryCountsAndKeyOrder() throws {
    for count in [0, 3, 1000] {
        let text = "{ \"completedSessions\": \(count), \"schemaVersion\": 1 }"
        #expect(try FocusSessionsContract.decode(Data(text.utf8)) == count)
    }
}

@Test
func nonfiniteClockAndPrecancelDoNotInvoke() async throws {
    let client   = RecordingClient()
    let provider = try ServiceConsumerProvider(
        owner     : owner,
        assignment: assignment,
        clock     : { Date(timeIntervalSince1970: .infinity) }
    )
    await #expect(throws: (any Error).self) {
        try await provider.handle(.refresh(assignment), context: context(client, [grant()]))
    }

    let consumer = try ServiceConsumerProvider(
        owner     : owner,
        assignment: assignment,
        clock     : { instant }
    )
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await consumer.handle(.refresh(assignment), context: context(client, [grant()]))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await client.count() == 0)
}

@Test
func codecByteCeilingAndInvalidUTF8() throws {
    let response = try FocusSessionsContract.syntheticResponse()
    var bytes    = response.payload
    bytes.append(Data(repeating: 32, count: 256 - bytes.count))
    #expect(try FocusSessionsContract.decode(bytes) == 3)

    bytes.append(32)
    #expect(throws: (any Error).self) { try FocusSessionsContract.decode(bytes) }
    #expect(throws: (any Error).self) { try FocusSessionsContract.decode(Data([255])) }

    for value in [
        #"{"schemaVersion":true,"completedSessions":3}"#,
        #"{"schemaVersion":1,"completedSessions":3.0}"#,
        #"{"schemaVersion":1,"completedSessions":3e0}"#,
        #"{"schemaVersion":1,"completedSessions":null}"#,
        #"{"schemaVersion":1,"schemaVersion":1,"completedSessions":3}"#
    ] {
        #expect(throws: (any Error).self) { try FocusSessionsContract.decode(Data(value.utf8)) }
    }
}

@Test
func rendezvousReportsEarlyCompletionAndFailure() async throws {
    let empty = try ProviderOutput(
        schemaVersion: 1,
        publications : [],
        operations   : [],
        completion   : nil,
        checkpoint   : nil
    )
    let failure = AddonFailure(code: .invalidPayload, reason: "Early refresh fixture")

    for fails in [false, true] {
        let client = RecordingClient(suspended: true)
        try await withObservedRefresh(client: client, operation: {
            if fails { throw failure }
            return empty
        }) { signal, task in
            guard case .completed(let result) = signal else {
                Issue.record("A refresh without an invocation must report its terminal result")
                return
            }

            #expect(throws: RefreshHarnessFailure.self) { try requireInvocation(signal) }
            if fails {
                #expect(throws: failure) { try result.get() }
                await #expect(throws: failure) { try await task.value }
            } else {
                let observed = try result.get()
                let returned = try await task.value
                #expect(observed == empty && returned == empty)
            }
        }
        #expect(await client.count() == 0)
        #expect(await !client.hasHeldWork())
    }
}

@Test
func rendezvousCleanupReleasesInvocationWhenBodyThrows() async throws {
    let client   = RecordingClient(suspended: true)
    let provider = try ServiceConsumerProvider(
        owner     : owner,
        assignment: assignment,
        clock     : { instant }
    )
    let addonContext = try context(client, [grant()])
    let failure      = AddonFailure(code: .invalidPayload, reason: "Test body fixture")

    await #expect(throws: failure) {
        try await withObservedRefresh(client: client, operation: {
            try await provider.handle(.refresh(assignment), context: addonContext)
        }) { signal, _ in
            try requireInvocation(signal)
            throw failure
        }
    }
    #expect(await client.count() == 1)
    #expect(await !client.hasHeldWork())

    // Cleanup awaited cancellation; a new refresh is no longer busy and has revision 1.
    let fresh  = RecordingClient()
    let output = try await provider.handle(.refresh(assignment), context: context(fresh, [grant()]))
    #expect(output.publications.first?.revision == 1)
}
