//
//  ExampleFixtures.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

let instant = Date(timeIntervalSince1970: 1_800_000_000)

let owner   = AddonID(rawValue: "com.example.serviceconsumer")!

let assignment = PublicationID(
    addonID   : owner,
    instanceID: UUID(),
    sessionID : UUID()
)

let generation = ConnectionGeneration()

func context(
    _ client: RecordingClient,
    _ grants: [Grant]
) throws -> AddonContext {
    try AddonContext(
        services  : client,
        storage   : UnavailableStorage(),
        generation: generation,
        grants    : grants
    )
}

func grant(
    owner grantOwner: AddonID = owner,
    service         : String = "com.example.focus.sessions",
    feature         : String = "summary",
    operation       : String = "read",
    expiry          : Date = instant.addingTimeInterval(10),
    gen             : ConnectionGeneration = generation
) throws -> Grant {
    try Grant(
        id        : UUID(),
        owner     : grantOwner,
        serviceID : service,
        scope     : ServiceScope(featureID: feature, operation: operation),
        expiresAt : expiry,
        generation: gen,
        cost      : AddonResourceRequest(
            profile              : .eventDriven,
            requestedMemoryMiB   : 0,
            maximumConcurrentWork: 1,
            background           : .none
        )
    )
}

func invocation(
    contract : String = "com.example.focus.sessions",
    operation: String = "read",
    payload  : Data = Data(),
    deadline : Date = instant.addingTimeInterval(2)
) throws -> ServiceInvocation {
    try ServiceInvocation(
        schemaVersion: 1,
        requestID    : UUID(),
        contractID   : contract,
        operation    : operation,
        payload      : payload,
        deadline     : deadline
    )
}

/// withObservedRefresh owns one refresh task, including cleanup when the test
/// body throws.
/// Arbitrary noncooperative work is still subject to the external test-run bound.
func withObservedRefresh(
    client   : RecordingClient,
    operation: @escaping @Sendable () async throws -> ProviderOutput,
    body     : (RefreshSignal, Task<ProviderOutput, any Error>) async throws -> Void
) async throws {
    let task = Task {
        do {
            let output = try await operation()
            await client.refreshFinished(.success(output))
            return output
        } catch {
            await client.refreshFinished(.failure(error))
            throw error
        }
    }

    let signal = await client.invokedOrFinished()
    let result: Result<Void, any Error>
    do {
        try await body(signal, task)
        result = .success(())
    } catch {
        result = .failure(error)
    }

    task.cancel()
    await client.release()
    _ = await task.result
    try result.get()
}

func requireInvocation(_ signal: RefreshSignal) throws {
    guard case .invoked = signal else { throw RefreshHarnessFailure.completedBeforeInvocation }
}

func expectFailureCode(
    _ code   : AddonFailure.Code,
    operation: () async throws -> ProviderOutput
) async {
    do {
        let output = try await operation()
        Issue.record("Expected \(code), received output: \(output)")
    } catch {
        #expect((error as? AddonFailure)?.code == code)
    }
}
