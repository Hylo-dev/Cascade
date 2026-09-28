import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

let instant = Date(timeIntervalSince1970: 1_800_000_000)
let owner = AddonID(rawValue: "com.example.serviceconsumer")!
let assignment = PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID())
let generation = ConnectionGeneration()
struct UnavailableStorage: AddonStorageClient {
 func read(key: String) async throws -> Data? { Issue.record("Unexpected storage read"); throw CancellationError() }
 func write(_ data: Data, key: String) async throws { Issue.record("Unexpected storage write"); throw CancellationError() }
 func remove(key: String) async throws { Issue.record("Unexpected storage remove"); throw CancellationError() }
}
actor RecordingClient: AddonServiceClient {
 var calls: [(ServiceInvocation, Grant)] = []
 let failure: AddonFailure?
 let response: ServiceResponse?
 let suspended: Bool
 private var waiter: CheckedContinuation<Void, Never>?
 private var signal: RefreshSignal?
 private var observer: CheckedContinuation<RefreshSignal, Never>?
 private var released = false
 init(failure: AddonFailure? = nil, response: ServiceResponse? = nil, suspended: Bool = false) { self.failure = failure; self.response = response; self.suspended = suspended }
 func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse {
  calls.append((invocation, grant))
  if suspended && !released {
   await withCheckedContinuation {
    waiter = $0
    publish(.invoked)
   }
  }
  if let failure { throw failure }
  if let response { return response }
  let provider = FocusSessionsExampleProvider(clock: { instant })
  let result = try await provider.handle(.serviceRequest(invocation), context: context(self, []))
  let completion = try #require(result.completion)
  try completion.validateCorrelation(.service(requestID: invocation.requestID, contractID: invocation.contractID, operation: invocation.operation))
  #expect(result.publications.isEmpty && result.operations.isEmpty && result.checkpoint == nil)
  guard case .service(_, let response) = completion else { throw CancellationError() }
  return response
 }
 // One rendezvous per client: cache the first signal so either arrival order works.
 private func publish(_ next: RefreshSignal) {
  guard signal == nil else { return }
  signal = next
  observer?.resume(returning: next)
  observer = nil
 }
 func refreshFinished(_ result: Result<ProviderOutput, any Error>) { publish(.completed(result)) }
 func invokedOrFinished() async -> RefreshSignal {
  if let signal { return signal }
  return await withCheckedContinuation { observer = $0 }
 }
 func release() { released = true; waiter?.resume(); waiter = nil }
 func hasHeldWork() -> Bool { waiter != nil || observer != nil }
 func count() -> Int { calls.count }
 func subscribe(requirementID: String, grant: Grant) async throws -> UUID { Issue.record("Unexpected subscription"); throw CancellationError() }
 func unsubscribe(subscriptionID: UUID) async throws { Issue.record("Unexpected unsubscribe"); throw CancellationError() }
}
func context(_ client: RecordingClient, _ grants: [Grant]) throws -> AddonContext {
 try AddonContext(services: client, storage: UnavailableStorage(), generation: generation, grants: grants)
}
func grant(owner grantOwner: AddonID = owner, service: String = "com.example.focus.sessions", feature: String = "summary", operation: String = "read", expiry: Date = instant.addingTimeInterval(10), gen: ConnectionGeneration = generation) throws -> Grant {
 try Grant(id: UUID(), owner: grantOwner, serviceID: service, scope: ServiceScope(featureID: feature, operation: operation), expiresAt: expiry, generation: gen, cost: AddonResourceRequest(profile: .eventDriven, requestedMemoryMiB: 0, maximumConcurrentWork: 1, background: .none))
}
func invocation(contract: String = "com.example.focus.sessions", operation: String = "read", payload: Data = Data(), deadline: Date = instant.addingTimeInterval(2)) throws -> ServiceInvocation {
 try ServiceInvocation(schemaVersion: 1, requestID: UUID(), contractID: contract, operation: operation, payload: payload, deadline: deadline)
}

final class CivilClock: @unchecked Sendable {
 private let lock = NSLock()
 private var value = instant
 func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
 func advance(to date: Date) { lock.lock(); defer { lock.unlock() }; value = date }
}

/// The first signal is either a held invocation or a terminal refresh result.
enum RefreshSignal: Sendable {
 case invoked
 case completed(Result<ProviderOutput, any Error>)
}

enum RefreshHarnessFailure: Error { case completedBeforeInvocation }

/// Owns one refresh task, including cleanup when the test body throws.
/// Arbitrary noncooperative work is still subject to the external test-run bound.
func withObservedRefresh(
 client: RecordingClient,
 operation: @escaping @Sendable () async throws -> ProviderOutput,
 body: (RefreshSignal, Task<ProviderOutput, any Error>) async throws -> Void
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
 do { try await body(signal, task); result = .success(()) }
 catch { result = .failure(error) }
 task.cancel()
 await client.release()
 _ = await task.result
 try result.get()
}

func requireInvocation(_ signal: RefreshSignal) throws {
 guard case .invoked = signal else { throw RefreshHarnessFailure.completedBeforeInvocation }
}

func expectFailureCode(
 _ code: AddonFailure.Code,
 operation: () async throws -> ProviderOutput
) async {
 do {
  let output = try await operation()
  Issue.record("Expected \(code), received output: \(output)")
 } catch {
  #expect((error as? AddonFailure)?.code == code)
 }
}
