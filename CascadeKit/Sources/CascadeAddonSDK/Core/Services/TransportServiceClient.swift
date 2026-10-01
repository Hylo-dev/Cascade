//
//  TransportServiceClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// TransportServiceClient is the complete message client for one canonical cumulative
/// 1.4 connection. The host remains grant authority. The embedding owns the paid
/// lifetime of running handlers.
public final class TransportServiceClient: AddonServiceClient, @unchecked Sendable {

    private struct Subscription {

        let requirementID: String
        let grant        : Grant
        let nonce        : UUID
    }

    private struct PendingSubscribe {

        let nonce        : UUID
        let requirementID: String
        let grant        : Grant
        var event        : ServiceEvent?
    }

    private struct PendingUnsubscribe {

        let id          : UUID
        let subscription: Subscription

        // Transfers the alias's existing paid latest-event scope; no second queue.
        var event: ServiceEvent?
    }

    private let channel : any AddonServiceMessageChannel
    private let exchange: ServiceConnectionExchange
    private let owner   : AddonID
    private let handler : @Sendable (ServiceEvent) async -> Void
    private let lock     = NSLock()

    private var subscriptions: [UUID: Subscription] = [:]
    private var quarantined  : Set<UUID> = []
    private var pending      : [UUID: (ServiceEvent, UUID)] = [:]
    private var subscribing  : PendingSubscribe?
    private var unsubscribing: PendingUnsubscribe?
    private var pumping       = false
    private var closed        = false

    public init(
        channel    : any AddonServiceMessageChannel,
        owner      : AddonID,
        handleEvent: @escaping @Sendable (ServiceEvent) async -> Void
    ) throws {
        self.channel = channel
        self.owner   = owner
        handler      = handleEvent
        exchange     = try ServiceConnectionExchange(channel: channel)

        try channel.bindServiceEvents { [weak self] bytes in
            guard let self else { return }

            try self.receive(bytes)
        }
    }

    private func validate(_ grant: Grant) throws {
        try grant.validate()
        try grant.scope.validate()
        guard grant.owner == owner,
              grant.generation == exchange.generation,
              channel.generation == exchange.generation,
              channel.invocationProfile == .v1_3,
              channel.subscriptionProfile == .v1_4
        else { throw Self.failure(.permissionDenied) }
        guard !lock.withLock({ closed }) else { throw Self.failure(.sessionRevoked) }
    }

    public func invoke(
        _ invocation: ServiceInvocation,
        grant       : Grant
    ) async throws -> ServiceResponse {
        try validate(grant)
        guard invocation.contractID == grant.serviceID,
              invocation.operation == grant.scope.operation
        else {
            throw Self.failure(.permissionDenied)
        }

        switch try await exchange.invoke(grantID: grant.id, invocation: invocation) {
            case .completed(let response): return response
            case .refused(let code, let reason): throw AddonFailure(code: code, reason: reason)
            case .outcomeUnknown: throw Self.failure(.outcomeUnknown)
        }
    }

    public func subscribe(
        requirementID: String,
        grant        : Grant
    ) async throws -> UUID {
        try validate(grant)

        let request = try ServiceControlRequest(
            requestID: UUID(),
            action   : .subscribe(requirementID: requirementID, grantID: grant.id)
        )
        let nonce   = UUID()

        try lock.withLock {
            guard !closed,
                  subscribing == nil,
                  unsubscribing == nil
            else { throw Self.failure(.resourceDenied) }
            guard subscriptions.count + quarantined.count < 64
                  || subscriptions.values.contains(where: {
                      $0.requirementID == requirementID && $0.grant.scope == grant.scope
                  })
            else { throw Self.failure(.resourceDenied) }

            subscribing = PendingSubscribe(
                nonce        : nonce,
                requirementID: requirementID,
                grant        : grant
            )
        }
        defer {
            lock.withLock { if subscribing?.nonce == nonce { subscribing = nil } }
        }

        let reply = try await exchange.control(request) { [self] reply in
            try lock.withLock {
                guard !closed,
                      let pendingSubscribe = subscribing,
                      pendingSubscribe.nonce == nonce
                else { throw Self.failure(.sessionRevoked) }

                if case .subscribed(let id) = reply.result {
                    guard !quarantined.contains(id) else { throw Self.failure(.permissionDenied) }

                    let previous = subscriptions[id]
                    if let old = previous {
                        guard old.requirementID == requirementID,
                              old.grant.scope == grant.scope,
                              old.grant.serviceID == grant.serviceID
                        else { throw Self.failure(.permissionDenied) }
                    } else {
                        guard subscriptions.count + quarantined.count < 64
                        else { throw Self.failure(.resourceDenied) }
                    }

                    let queued        = pending.removeValue(forKey: id)
                    subscriptions[id] = Subscription(
                        requirementID: requirementID,
                        grant        : grant,
                        nonce        : nonce
                    )
                    if let event = pendingSubscribe.event, event.subscriptionID == id, event.token == grant {
                        pending[id] = (event, nonce)
                    } else if let previous, previous.grant == grant,
                              let (event, oldNonce) = queued, oldNonce == previous.nonce,
                              event.subscriptionID == id, event.token == grant {
                        // A same-grant refresh confirms the same authority. Transfer
                        // its already-paid latest value to the new local nonce.
                        pending[id] = (event, nonce)
                    }
                    subscribing = nil
                }
            }
        }

        switch reply.result {
            case .subscribed(let id):
                startPump()
                return id

            case .refused(let code, let reason): throw AddonFailure(code: code, reason: reason)
            default: throw Self.failure(.outcomeUnknown)
        }
    }

    public func unsubscribe(subscriptionID: UUID) async throws {
        let removed: Subscription = try lock.withLock {
            guard unsubscribing == nil, subscribing == nil else { throw Self.failure(.resourceDenied) }
            guard !closed,
                  let existing = subscriptions.removeValue(forKey: subscriptionID)
            else { throw Self.failure(.permissionDenied) }

            unsubscribing = PendingUnsubscribe(
                id          : subscriptionID,
                subscription: existing,
                event       : pending.removeValue(forKey: subscriptionID)?.0
            )
            return existing
        }

        do {
            let request = try ServiceControlRequest(
                requestID: UUID(),
                action   : .unsubscribe(subscriptionID: subscriptionID)
            )
            let reply   = try await exchange.control(request)

            switch reply.result {
                case .acknowledged:
                    finishUnsubscribe(
                        subscriptionID,
                        nonce     : removed.nonce,
                        restore   : false,
                        quarantine: false
                    )
                    return

                case .refused(let code, let reason): throw AddonFailure(code: code, reason: reason)
                default: throw Self.failure(.outcomeUnknown)
            }
        } catch {
            // Unknown exposure quarantines this handle for the remainder of the connection.
            if (error as? AddonFailure)?.code == .outcomeUnknown {
                finishUnsubscribe(
                    subscriptionID,
                    nonce     : removed.nonce,
                    restore   : false,
                    quarantine: true
                )
            } else {
                finishUnsubscribe(
                    subscriptionID,
                    nonce     : removed.nonce,
                    restore   : true,
                    quarantine: false
                )
            }

            throw error
        }
    }

    private func finishUnsubscribe(
        _ id      : UUID,
        nonce     : UUID,
        restore   : Bool,
        quarantine: Bool
    ) {
        lock.withLock {
            guard let held = unsubscribing,
                  held.id == id,
                  held.subscription.nonce == nonce
            else { return }

            unsubscribing = nil
            guard !closed else { return }

            if quarantine { quarantined.insert(id) }
            if restore, subscriptions[id] == nil {
                subscriptions[id] = held.subscription
                if let event = held.event { pending[id] = (event, held.subscription.nonce) }
            }
        }

        if restore { startPump() }
    }

    /// acquireContext is embedding plumbing for fresh context assembly, not a new
    /// service protocol method.
    func acquireContext(
        operations: [OperationRequest],
        storage   : any AddonStorageClient,
        assets    : any AddonAssetClient
    ) async throws -> AddonContext {
        guard operations.count <= 64 else { throw Self.failure(.resourceDenied) }

        var grants: [Grant] = []
        for operation in operations {
            let grant = try await exchange.acquire(operation, owner: owner)
            try validate(grant)
            grants.append(grant)
        }

        return try AddonContext(
            services  : self,
            storage   : storage,
            assets    : assets,
            generation: exchange.generation,
            grants    : grants
        )
    }

    private func receive(_ bytes: Data) throws {
        let event = try ServiceSubscriptionFrameCodec.decodeServiceEvent(
            bytes,
            profile: channel.subscriptionProfile
        )
        try validate(event.token)

        try lock.withLock {
            guard !closed else { throw Self.failure(.sessionRevoked) }

            if let subscription = subscriptions[event.subscriptionID], subscription.grant == event.token {
                pending[event.subscriptionID] = (event, subscription.nonce)
            } else if var held = unsubscribing,
                      held.id == event.subscriptionID,
                      held.subscription.grant == event.token {
                // Receipt already retired physically. Suppress callbacks until the
                // control outcome decides whether to restore or discard this latest.
                held.event    = event
                unsubscribing = held
            } else if var current = subscribing, current.grant == event.token {
                // One bounded candidate under the pending subscribe operation. Never adopt
                // its ID; only the independently correlated terminal reply can install it.
                guard current.event == nil || current.event?.subscriptionID == event.subscriptionID
                else { throw Self.failure(.permissionDenied) }

                current.event = event
                subscribing   = current
            } else {
                throw Self.failure(.permissionDenied)
            }
        }

        startPump()
    }

    private func startPump() {
        lock.withLock {
            guard !closed, !pumping, !pending.isEmpty else { return }

            pumping = true
            Task { await self.pump() }
        }
    }

    private func pump() async {
        var last: UUID?
        while true {
            let next: ServiceEvent? = lock.withLock {
                while !closed {
                    let ids = pending.keys.sorted { $0.uuidString < $1.uuidString }
                    guard let id = ids.first(where: { last == nil || $0.uuidString > last!.uuidString }) ?? ids.first,
                          let (event, nonce) = pending.removeValue(forKey: id)
                    else { break }

                    last = id
                    guard subscriptions[id]?.nonce == nonce,
                          subscriptions[id]?.grant == event.token,
                          event.token.generation == exchange.generation,
                          channel.generation == exchange.generation
                    else { continue }

                    return event
                }

                pumping = false
                return nil
            }
            guard let next else { return }

            // Receipt/staging disposal precede reception. User code runs without a lock or exchange slot.
            await handler(next)
        }
    }

    public func close() async {
        lock.withLock {
            closed = true
            subscriptions.removeAll()
            quarantined.removeAll()
            pending.removeAll()
            subscribing   = nil
            unsubscribing = nil
        }

        await exchange.close()
        // Running user code is neither cancelled nor joined from its own callback.
    }

    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "The service client rejected this operation"
        )
    }
}
