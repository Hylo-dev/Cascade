//
//  SubscriptionHandlerBox.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

actor SubscriptionHandlerBox {
    private var context: AddonContext?
    private var invocation: ServiceInvocation?
    private var alias: UUID?
    private var waiter: CheckedContinuation<Void, Never>?
    private var initialWaiter: CheckedContinuation<Void, Never>?
    private var initialReceived = false
    var finished = false
    var payloadBytes = 0
    var failure: String?
    func install(context: AddonContext, invocation: ServiceInvocation, alias: UUID) {
        self.context = context; self.invocation = invocation; self.alias = alias
    }
    func handle(_ event: ServiceEvent) async {
        payloadBytes = event.response.payload.count
        if context == nil {
            initialReceived = true; initialWaiter?.resume(); initialWaiter = nil
            return
        }
        do {
            let context = try #require(context), invocation = try #require(invocation), alias = try #require(alias)
            _ = try await context.services.invoke(invocation, grant: event.token)
            try await context.services.unsubscribe(subscriptionID: alias)
            // Closing from the active handler must not join its own dispatch pump.
            await (context.services as? TransportServiceClient)?.close()
        } catch { failure = String(describing: error) }
        finished = true; waiter?.resume(); waiter = nil
    }
    func waitForInitial() async { if !initialReceived { await withCheckedContinuation { initialWaiter = $0 } } }
    func wait() async { if !finished { await withCheckedContinuation { waiter = $0 } } }
}
