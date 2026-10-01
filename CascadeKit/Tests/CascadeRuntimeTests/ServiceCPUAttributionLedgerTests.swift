//
//  ServiceCPUAttributionLedgerTests.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ServiceCPUAttributionLedgerTests {
    @Test func activeChainsDiamondsSelfEdgesAndCyclesDeduplicate() throws {
        let owners = try identities("a", "b", "c", "d")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        _ = try ledger.register(binding, physicalOwner: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[1], provider: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[1])
        _ = try ledger.addInterest(UUID(), consumer: owners[3], provider: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[3])
        _ = try ledger.addInterest(UUID(), consumer: owners[0], provider: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[0], provider: owners[2])
        let recipients = try ledger.withObservation(for: binding) { $0 }
        #expect(recipients == [owners[1], owners[2], owners[3]])
        #expect(try ledger.withObservation(for: binding) { $0 } == recipients)
    }

    @Test func separateInterestIDsKeepAnEdgeAliveUntilBothRetire() throws {
        let owners = try identities("a", "b")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let first = UUID()
        let second = UUID()
        _ = try ledger.register(binding, physicalOwner: owners[0])
        #expect(try ledger.addInterest(first, consumer: owners[1], provider: owners[0]))
        #expect(!(try ledger.addInterest(first, consumer: owners[1], provider: owners[0])))
        #expect(try ledger.addInterest(second, consumer: owners[1], provider: owners[0]))
        #expect(ledger.removeInterest(first))
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
        #expect(ledger.removeInterest(second))
        #expect(!ledger.removeInterest(second))
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
    }

    @Test func edgesFromDifferentInstantsCannotMakePhantomChain() throws {
        let owners = try identities("a", "b", "c")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let first = UUID()
        _ = try ledger.register(binding, physicalOwner: owners[0])
        _ = try ledger.addInterest(first, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(first))
        _ = try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[1])
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
    }

    @Test func wholeChainBeginningAndEndingBetweenReadsIsRetainedOnce() throws {
        let owners = try identities("a", "b", "c")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let first = UUID()
        let second = UUID()
        _ = try ledger.register(binding, physicalOwner: owners[0])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
        _ = try ledger.addInterest(first, consumer: owners[1], provider: owners[0])
        _ = try ledger.addInterest(second, consumer: owners[2], provider: owners[1])
        #expect(ledger.removeInterest(first))
        #expect(ledger.removeInterest(second))
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1], owners[2]])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
    }

    @Test func eachPhysicalBindingKeepsItsOwnIntervalHistory() throws {
        let owners = try identities("a", "b", "c", "d")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let first = metricBinding(1)
        let second = metricBinding(2)
        let firstID = UUID()
        let secondID = UUID()
        _ = try ledger.register(first, physicalOwner: owners[0])
        _ = try ledger.register(second, physicalOwner: owners[2])
        _ = try ledger.addInterest(firstID, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(firstID))
        _ = try ledger.addInterest(secondID, consumer: owners[3], provider: owners[2])
        #expect(ledger.removeInterest(secondID))
        #expect(try ledger.withObservation(for: first) { $0 } == [owners[1]])
        #expect(try ledger.withObservation(for: second) { $0 } == [owners[3]])
        #expect(try ledger.withObservation(for: first) { $0 }.isEmpty)
        #expect(try ledger.withObservation(for: second) { $0 }.isEmpty)
    }

    @Test func duplicateBindingPreservesHistoryAndForgedIncarnationsFail() throws {
        let owners = try identities("a", "b")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let forged = ProcessMetricBinding(
            pid               : binding.pid,
            birthAbsoluteTicks: binding.birthAbsoluteTicks + 1,
            executableUUID    : binding.executableUUID,
            token             : binding.token,
            clockDomain       : binding.clockDomain
        )
        _ = try ledger.register(binding, physicalOwner: owners[0])
        let interest = UUID()
        _ = try ledger.addInterest(interest, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(interest))
        #expect(!(try ledger.register(binding, physicalOwner: owners[0])))
        #expect(throws: ServiceCPUAttributionLedger.Failure.bindingConflict) {
            try ledger.register(binding, physicalOwner: owners[1])
        }
        #expect(throws: ServiceCPUAttributionLedger.Failure.tokenConflict) {
            try ledger.register(forged, physicalOwner: owners[0])
        }
        #expect(!ledger.unregister(forged))
        #expect(throws: ServiceCPUAttributionLedger.Failure.unregisteredBinding) {
            try ledger.withObservation(for: forged) { $0 }
        }
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
        #expect(ledger.unregister(binding))
        #expect(!ledger.unregister(binding))
    }

    @Test func badDomainInterestAndCapacityRejectBeforeMutation() throws {
        let owners = try identities("a", "b", "c")
        let conflicting = VerifiedAddonIdentity(publisher: "other.publisher", addonID: owners[0].addonID)
        #expect(throws: ServiceCPUAttributionLedger.Failure.invalidOwnerDomain) {
            try ServiceCPUAttributionLedger(authorizedOwners: [owners[0], conflicting])
        }
        #expect(throws: ServiceCPUAttributionLedger.Failure.invalidOwnerDomain) {
            try ServiceCPUAttributionLedger(authorizedOwners: [owners[0], owners[0]])
        }
        #expect(throws: ServiceCPUAttributionLedger.Failure.invalidOwnerDomain) {
            try ServiceCPUAttributionLedger(authorizedOwners: Array(repeating: owners[0], count: 33))
        }
        let whitespace = VerifiedAddonIdentity(publisher: "   ", addonID: owners[0].addonID)
        #expect(throws: ServiceCPUAttributionLedger.Failure.invalidOwnerDomain) {
            try ServiceCPUAttributionLedger(authorizedOwners: [whitespace])
        }
        let ledger = try ServiceCPUAttributionLedger(
            authorizedOwners: [owners[0], owners[1]],
            maximumBindings: 1,
            maximumInterests: 1
        )
        #expect(ledger.authorizedOwners == [owners[0], owners[1]])
        let binding = metricBinding(1)
        _ = try ledger.register(binding, physicalOwner: owners[0])
        let firstID = UUID()
        #expect(try ledger.addInterest(firstID, consumer: owners[1], provider: owners[0]))
        #expect(throws: ServiceCPUAttributionLedger.Failure.conflictingInterest) {
            try ledger.addInterest(firstID, consumer: owners[0], provider: owners[1])
        }
        #expect(throws: ServiceCPUAttributionLedger.Failure.interestCapacityReached) {
            try ledger.addInterest(UUID(), consumer: owners[1], provider: owners[0])
        }
        #expect(throws: ServiceCPUAttributionLedger.Failure.invalidOwner) {
            try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[0])
        }
        #expect(throws: ServiceCPUAttributionLedger.Failure.bindingCapacityReached) {
            try ledger.register(metricBinding(2), physicalOwner: owners[0])
        }
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
        #expect(ledger.removeInterest(firstID))
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
    }

    @Test func thrownObservationRetainsHistoryAndWakeSeedsOnlyLiveChain() throws {
        let owners = try identities("a", "b", "c")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let old = metricBinding(1)
        let fresh = metricBinding(2)
        let ended = UUID()
        _ = try ledger.register(old, physicalOwner: owners[0])
        _ = try ledger.addInterest(ended, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(ended))
        enum Expected: Error { case interrupted }
        #expect(throws: Expected.interrupted) {
            try ledger.withObservation(for: old) { _ -> Void in throw Expected.interrupted }
        }
        #expect(try ledger.withObservation(for: old) { $0 } == [owners[1]])
        let active = UUID()
        _ = try ledger.addInterest(active, consumer: owners[2], provider: owners[0])
        #expect(ledger.unregister(old))
        _ = try ledger.register(fresh, physicalOwner: owners[0])
        #expect(try ledger.withObservation(for: fresh) { $0 } == [owners[2]])
        _ = try ledger.addInterest(ended, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(ended))
        ledger.resetAfterWake()
        #expect(try ledger.withObservation(for: fresh) { $0 } == [owners[2]])
        #expect(ledger.removeInterest(active))
        #expect(try ledger.withObservation(for: fresh) { $0 } == [owners[2]])
        #expect(try ledger.withObservation(for: fresh) { $0 }.isEmpty)
    }

    @Test func membershipMutationWaitsForSingleObservationCommit() throws {
        let owners = try identities("a", "b")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        _ = try ledger.register(binding, physicalOwner: owners[0])
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let observingDone = DispatchSemaphore(value: 0)
        let mutatingStarted = DispatchSemaphore(value: 0)
        let mutatingDone = DispatchSemaphore(value: 0)
        let recipientBox = RecipientBox()
        let observation = DispatchQueue(label: "ledger-observation")
        let mutation = DispatchQueue(label: "ledger-mutation")
        observation.async {
            defer { observingDone.signal() }
            do {
                let recipients = try ledger.withObservation(for: binding) { recipients in
                    entered.signal()
                    guard release.wait(timeout: .now() + 2) == .success else {
                        Issue.record("Observation release timed out.")
                        return recipients
                    }
                    return recipients
                }
                recipientBox.store(recipients)
            } catch {
                Issue.record("Observation failed: \(error)")
            }
        }
        defer { release.signal() }
        guard entered.wait(timeout: .now() + 2) == .success else {
            Issue.record("Observation did not enter its synchronous body.")
            return
        }
        mutation.async {
            defer { mutatingDone.signal() }
            mutatingStarted.signal()
            do {
                _ = try ledger.addInterest(UUID(), consumer: owners[1], provider: owners[0])
            } catch {
                Issue.record("Membership mutation failed: \(error)")
            }
        }
        #expect(mutatingStarted.wait(timeout: .now() + 2) == .success)
        #expect(mutatingDone.wait(timeout: .now() + .milliseconds(20)) == .timedOut)
        release.signal()
        #expect(observingDone.wait(timeout: .now() + 2) == .success)
        #expect(mutatingDone.wait(timeout: .now() + 2) == .success)
        #expect(recipientBox.value == [])
        #expect(try ledger.withObservation(for: binding) { $0 } == [owners[1]])
    }

    private func identities(_ names: String...) throws -> [VerifiedAddonIdentity] {
        try names.map { name in
            VerifiedAddonIdentity(
                publisher: "verified.publisher",
                addonID  : try #require(AddonID(rawValue: "com.example.\(name)"))
            )
        }
    }

    private func metricBinding(_ index: UInt8) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid               : Int32(40 + index),
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)),
            token             : UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, index)),
            clockDomain       : UUID(uuid: (3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3))
        )
    }
}
