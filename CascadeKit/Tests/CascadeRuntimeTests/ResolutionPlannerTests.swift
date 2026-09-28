import Foundation
import Testing
import CascadeContracts
import CascadeRuntime

@Suite("ResolutionPlanner") struct ResolutionPlannerTests {
    @Test func keepsAutonomousFeatureWhenSourceApplicationIsAbsent() throws {
        let addon = try installedFixture("optional-consumer")
        let result = try ResolutionPlanner.resolve(catalog: [addon], environment: emptyEnvironment, prior: [])
        #expect(result.acceptedAddons == [addon.manifest.id])
        #expect(result.blockedFeatures.map(\.featureID) == ["openInSourceApp"])
        #expect(result.enabledFeatures.map(\.featureID) == ["localTimer"])
    }

    @Test func resolvesServiceAndStartsProviderBeforeConsumer() throws {
        let focus = try installedFixture("focus")
        let consumer = try installedFixture("consumer")
        let result = try ResolutionPlanner.resolve(catalog: [consumer, focus], environment: emptyEnvironment, prior: [])
        #expect(result.startOrder == [focus.manifest.id, consumer.manifest.id])
        #expect(result.bindings.count == 1)
        #expect(result.reverseDependents[focus.manifest.id] == [consumer.manifest.id])
    }

    @Test func stableOrderingSurvivesSeededCatalogPermutations() throws {
        let focus = try installedFixture("focus")
        let second = try replacing(focus, id: "com.example.focus-second")
        let consumer = try installedFixture("consumer")
        let baseline = try ResolutionPlanner.resolve(catalog: [focus, second, consumer], environment: emptyEnvironment, prior: [])
        var generator = SeededGenerator(seed: 0xCA5CADE)
        for _ in 0..<40 {
            let shuffled = [focus, second, consumer].shuffled(using: &generator)
            #expect(try ResolutionPlanner.resolve(catalog: shuffled, environment: emptyEnvironment, prior: []) == baseline)
        }
    }

    @Test func validPriorBindingWinsStableCandidateOrder() throws {
        let focus = try installedFixture("focus")
        let second = try replacing(focus, id: "com.example.focus-second")
        let consumer = try installedFixture("consumer")
        let prior = ServiceBinding(requirementID: "com.example.focus.sessions", consumer: consumer.manifest.id, provider: second.manifest.id, providerIdentity: second.verifiedIdentity, contractVersion: SemanticVersion(1, 0, 0), digest: second.digest)
        let result = try ResolutionPlanner.resolve(catalog: [focus, second, consumer], environment: emptyEnvironment, prior: [prior])
        #expect(result.bindings.first?.provider == second.manifest.id)
    }

    @Test func hostServiceWinsStableAddonCandidateAfterPersistedChoices() throws {
        let focus = try installedFixture("focus")
        let consumer = try installedFixture("consumer")
        var environment = emptyEnvironment
        environment = HostEnvironment(osVersion: environment.osVersion, hostCapabilities: ["com.example.focus.sessions": SemanticVersion(1, 1, 0)], applications: environment.applications, grants: environment.grants, explicitBindings: [])
        let result = try ResolutionPlanner.resolve(catalog: [focus, consumer], environment: environment, prior: [])
        #expect(result.bindings.first?.provider == AddonID(rawValue: "app.cascade.host"))
        #expect(result.startOrder == [consumer.manifest.id, focus.manifest.id])
    }

    @Test func explicitBindingWinsPriorBinding() throws {
        let focus = try installedFixture("focus")
        let second = try replacing(focus, id: "com.example.focus-second")
        let consumer = try installedFixture("consumer")
        let prior = ServiceBinding(requirementID: "com.example.focus.sessions", consumer: consumer.manifest.id, provider: second.manifest.id, providerIdentity: second.verifiedIdentity, contractVersion: SemanticVersion(1, 0, 0), digest: second.digest)
        let explicit = ServiceBinding(requirementID: "com.example.focus.sessions", consumer: consumer.manifest.id, provider: focus.manifest.id, providerIdentity: focus.verifiedIdentity, contractVersion: SemanticVersion(1, 0, 0), digest: focus.digest)
        var environment = emptyEnvironment
        environment.explicitBindings = [explicit]
        let result = try ResolutionPlanner.resolve(catalog: [second, focus, consumer], environment: environment, prior: [prior])
        #expect(result.bindings.first?.provider == focus.manifest.id)
    }

    @Test func rejectsCycleAndVersionConflictAndDisabledProvider() throws {
        let base = try installedFixture("focus")
        let serviceA = try ProvidedService(kind: .service, id: "service.a", version: "1.0.0")
        let serviceB = try ProvidedService(kind: .service, id: "service.b", version: "1.0.0")
        let a = try replacing(base, id: "com.example.a", requires: [requirement("service.b", ">=1.0.0 <2.0.0")], provides: [serviceA])
        let b = try replacing(base, id: "com.example.b", requires: [requirement("service.a", ">=1.0.0 <2.0.0")], provides: [serviceB])
        let cycle = try ResolutionPlanner.resolve(catalog: [b, a], environment: emptyEnvironment, prior: [])
        #expect(cycle.acceptedAddons.isEmpty)
        #expect(cycle.blockedAddons.allSatisfy { $0.failure.code == .dependencyUnavailable })
        var generator = SeededGenerator(seed: 0xC1C1E)
        for _ in 0..<20 {
            #expect(try ResolutionPlanner.resolve(catalog: [a, b].shuffled(using: &generator), environment: emptyEnvironment, prior: []) == cycle)
        }

        let consumer = try installedFixture("consumer")
        let incompatible = try replacing(base, provides: [try ProvidedService(kind: .service, id: "com.example.focus.sessions", version: "2.0.0")])
        let conflict = try ResolutionPlanner.resolve(catalog: [consumer, incompatible], environment: emptyEnvironment, prior: [])
        #expect(conflict.blockedAddons.first(where: { $0.addonID == consumer.manifest.id })?.failure.code == .versionConflict)

        let disabled = try InstalledAddon(manifest: base.manifest, verifiedIdentity: base.verifiedIdentity, digest: base.digest, enabled: false)
        let unavailable = try ResolutionPlanner.resolve(catalog: [consumer, disabled], environment: emptyEnvironment, prior: [])
        #expect(unavailable.blockedAddons.first(where: { $0.addonID == consumer.manifest.id })?.failure.code == .dependencyUnavailable)
    }

    @Test func missingPermissionBlocksOnlyAffectedAddon() throws {
        let base = try installedFixture("focus")
        let permission = try AddonPermission(id: .storageOwn, scope: .addon)
        let protected = try replacing(base, permissions: [permission])
        let result = try ResolutionPlanner.resolve(catalog: [protected], environment: emptyEnvironment, prior: [])
        #expect(result.blockedAddons.first?.failure.code == .permissionDenied)
    }

    @Test func thirdPartyServiceRequiresTrustedIdentityGrant() throws {
        let provider = try installedFixture("focus", publisher: "TEST-ONLY.provider")
        let consumer = try installedFixture("consumer", publisher: "TEST-ONLY.consumer")
        let explicit = ServiceBinding(requirementID: "com.example.focus.sessions", consumer: consumer.manifest.id, provider: provider.manifest.id, providerIdentity: provider.verifiedIdentity, contractVersion: SemanticVersion(1, 0, 0), digest: provider.digest)
        let deniedEnvironment = HostEnvironment(osVersion: emptyEnvironment.osVersion, hostCapabilities: [:], applications: [:], grants: [:], explicitBindings: [explicit])
        let denied = try ResolutionPlanner.resolve(catalog: [provider, consumer], environment: deniedEnvironment, prior: [])
        #expect(denied.blockedAddons.first(where: { $0.addonID == consumer.manifest.id })?.failure.code == .dependencyUnavailable)
        let grant = ServiceAccessGrant(consumer: consumer.manifest.id, requirementID: "com.example.focus.sessions", providerIdentity: provider.verifiedIdentity)
        let allowedEnvironment = HostEnvironment(osVersion: emptyEnvironment.osVersion, hostCapabilities: [:], applications: [:], grants: [:], explicitBindings: [], serviceAccessGrants: [grant])
        let allowed = try ResolutionPlanner.resolve(catalog: [provider, consumer], environment: allowedEnvironment, prior: [])
        #expect(allowed.bindings.first?.providerIdentity == provider.verifiedIdentity)
        let wrongGrant = ServiceAccessGrant(consumer: consumer.manifest.id, requirementID: "com.example.focus.sessions", providerIdentity: VerifiedAddonIdentity(publisher: "TEST-ONLY.other", addonID: provider.manifest.id))
        let wrongEnvironment = HostEnvironment(osVersion: emptyEnvironment.osVersion, hostCapabilities: [:], applications: [:], grants: [:], explicitBindings: [], serviceAccessGrants: [wrongGrant])
        #expect(try ResolutionPlanner.resolve(catalog: [provider, consumer], environment: wrongEnvironment, prior: []).bindings.isEmpty)
    }

    @Test func identityMismatchIsRejected() throws {
        let base = try installedFixture("focus")
        #expect(throws: (any Error).self) {
            try InstalledAddon(manifest: base.manifest, verifiedIdentity: VerifiedAddonIdentity(publisher: "TEST-ONLY.publisher", addonID: AddonID(rawValue: "com.example.other")!), digest: "x", enabled: true)
        }
    }

    @Test func rejectsCatalogAndAlternativeSearchBeyondPolicy() throws {
        let base = try installedFixture("focus")
        let oversized = try (0..<1025).map { index in let item = try replacing(base, id: "com.example.item\(index)"); return try InstalledAddon(manifest: item.manifest, verifiedIdentity: item.verifiedIdentity, digest: item.digest, enabled: false) }
        #expect(throws: AddonFailure.self) { try ResolutionPlanner.resolve(catalog: oversized, environment: emptyEnvironment, prior: []) }

        let alternatives = try (0..<8).map { index in try RequirementAlternative(id: "alternative\(index)", requires: [try requirement("missing.\(index)", ">=1.0.0 <2.0.0")]) }
        let any = try AddonRequirement(kind: .anyOf, id: nil, version: nil, bundleID: nil, state: nil, anyOf: alternatives)
        let complex = try replacing(base, requires: [any])
        #expect(throws: AddonFailure.self) { try ResolutionPlanner.resolve(catalog: [complex], environment: emptyEnvironment, prior: [], policy: ResolutionPolicy(maximumAlternativeSteps: 3)) }
    }

    @Test func failedConjunctionDoesNotLeakDependencyEdges() throws {
        let provider = try installedFixture("focus")
        let consumer = try installedFixture("consumer")
        let broken = try replacing(consumer, requires: [try requirement("com.example.focus.sessions", ">=1.0.0 <2.0.0"), try requirement("missing.service", ">=1.0.0 <2.0.0")])
        let result = try ResolutionPlanner.resolve(catalog: [provider, broken], environment: emptyEnvironment, prior: [])
        #expect(result.bindings.isEmpty)
        #expect(result.reverseDependents.isEmpty)
    }

    @Test func triesLaterProviderAndHandlesPrereleaseWithoutCrash() throws {
        let base = try installedFixture("focus")
        let blocked = try replacing(base, id: "com.example.aaa", requires: [try requirement("missing.service", ">=1.0.0 <2.0.0")])
        let valid = try replacing(base, id: "com.example.zzz")
        let consumer = try installedFixture("consumer")
        let result = try ResolutionPlanner.resolve(catalog: [blocked, valid, consumer], environment: emptyEnvironment, prior: [])
        #expect(result.bindings.first?.provider == valid.manifest.id)
        #expect(SemanticVersionRange(">=1.0.0-beta <2.0.0")!.contains(SemanticVersion("1.0.0-beta.999999999999999999999999")!))
        #expect(SemanticVersion("1.0.0+one") == SemanticVersion("1.0.0+two"))
        #expect(SemanticVersion("1.0.0-099999999999999999999999") == nil)
    }

    @Test func acceptsLargeInactiveCatalogAndRejectsProtocolMismatch() throws {
        let base = try installedFixture("focus")
        let inactive = try (0..<100).map { index in let item = try replacing(base, id: "com.example.inactive\(index)"); return try InstalledAddon(manifest: item.manifest, verifiedIdentity: item.verifiedIdentity, digest: item.digest, enabled: false) }
        #expect(try ResolutionPlanner.resolve(catalog: inactive, environment: emptyEnvironment, prior: []).acceptedAddons.isEmpty)
        let oldHost = HostEnvironment(osVersion: SemanticVersion(14, 0, 0), hostCapabilities: [:], applications: [:], grants: [:], explicitBindings: [], protocolVersion: (1, -1))
        #expect(try ResolutionPlanner.resolve(catalog: [base], environment: oldHost, prior: []).blockedAddons.first?.failure.code == .versionConflict)
    }

    @Test func blocksFeatureEdgeThatWouldCloseCycle() throws {
        let base = try installedFixture("focus")
        let featureA = try AddonFeature(id: "featureA", requires: [try requirement("service.b", ">=1.0.0 <2.0.0")], actions: nil)
        let featureB = try AddonFeature(id: "featureB", requires: [try requirement("service.a", ">=1.0.0 <2.0.0")], actions: nil)
        let a = try replacing(base, id: "com.example.feature-a", provides: [try ProvidedService(kind: .service, id: "service.a", version: "1.0.0")], features: [featureA])
        let b = try replacing(base, id: "com.example.feature-b", provides: [try ProvidedService(kind: .service, id: "service.b", version: "1.0.0")], features: [featureB])
        let result = try ResolutionPlanner.resolve(catalog: [a, b], environment: emptyEnvironment, prior: [])
        #expect(result.blockedFeatures.count == 1)
        #expect(result.blockedFeatures[0].failure.reason.contains(" -> "))
        #expect(result.startOrder.count == 2)
    }

    @Test func cyclicFirstProviderBacktracksWithoutBlockingConsumer() throws {
        let base = try installedFixture("focus")
        let consumerService = try ProvidedService(kind: .service, id: "consumer.callback", version: "1.0.0")
        let consumer = try replacing(try installedFixture("consumer"), id: "com.example.consumer-backtrack", provides: [consumerService])
        let cyclic = try replacing(base, id: "com.example.aaa-cyclic", requires: [try requirement("consumer.callback", ">=1.0.0 <2.0.0")])
        let valid = try replacing(base, id: "com.example.zzz-valid")
        let result = try ResolutionPlanner.resolve(catalog: [cyclic, valid, consumer], environment: emptyEnvironment, prior: [])
        #expect(result.acceptedAddons.contains(consumer.manifest.id))
        #expect(!result.blockedAddons.contains(where: { $0.addonID == consumer.manifest.id }))
        #expect(result.bindings.first(where: { $0.consumer == consumer.manifest.id })?.provider == valid.manifest.id)
    }

    @Test func boundsFailedProviderBranchesWithoutAnyOf() throws {
        let base = try installedFixture("focus")
        let first = try replacing(base, id: "com.example.branch-a", requires: [try requirement("missing.a", ">=1.0.0 <2.0.0")])
        let second = try replacing(base, id: "com.example.branch-b", requires: [try requirement("missing.b", ">=1.0.0 <2.0.0")])
        let consumer = try installedFixture("consumer")
        #expect(throws: AddonFailure.self) {
            try ResolutionPlanner.resolve(catalog: [first, second, consumer], environment: emptyEnvironment, prior: [], policy: ResolutionPolicy(maximumAlternativeSteps: 1))
        }
    }

    @Test func keepsDistinctBindingsForFeatureVersionRanges() throws {
        let base = try installedFixture("focus")
        let v1 = try replacing(base, id: "com.example.service-v1", provides: [try ProvidedService(kind: .service, id: "shared.service", version: "1.2.0")])
        let v2 = try replacing(base, id: "com.example.service-v2", provides: [try ProvidedService(kind: .service, id: "shared.service", version: "2.1.0")])
        let one = try AddonFeature(id: "usesV1", requires: [try requirement("shared.service", ">=1.0.0 <2.0.0")], actions: nil)
        let two = try AddonFeature(id: "usesV2", requires: [try requirement("shared.service", ">=2.0.0 <3.0.0")], actions: nil)
        let consumer = try replacing(base, id: "com.example.feature-consumer", provides: [], features: [one, two])
        let result = try ResolutionPlanner.resolve(catalog: [consumer, v2, v1], environment: emptyEnvironment, prior: [])
        #expect(result.enabledFeatures.filter { $0.addonID == consumer.manifest.id }.count == 2)
        #expect(result.bindings.filter { $0.consumer == consumer.manifest.id && $0.requirementID == "shared.service" }.count == 2)
    }
    @Test func rejectedRootRestoresNestedProviderAdmission() throws {
        let a = try graphAddon("a", dependencies: ["b", "missing"])
        let b = try graphAddon("b", dependencies: ["c"])
        let c = try graphAddon("c")
        let result = try ResolutionPlanner.resolve(catalog: [a, b, c], environment: emptyEnvironment, prior: [])
        #expect(result.acceptedAddons == [b.manifest.id, c.manifest.id])
        #expect(result.bindings.map(\.consumer) == [b.manifest.id])
        #expect(result.bindings.map(\.provider) == [c.manifest.id])
        #expect(result.startOrder == [c.manifest.id, b.manifest.id])
    }

    @Test func cachedChainsRespectGraphDepth() throws {
        let chain = try (0...10).map { i in try graphAddon(String(format: "chain%02d", i), dependencies: i == 0 ? [] : [String(format: "chain%02d", i - 1)]) }
        let result = try ResolutionPlanner.resolve(catalog: chain, environment: emptyEnvironment, prior: [])
        #expect(result.acceptedAddons.count == 9)
        #expect(result.blockedAddons.count == 2)
    }

    @Test func featureGrowthChecksAncestorDepthAndClosure() throws {
        let leaf = try graphAddon("zleaf")
        let feature = try AddonFeature(id: "grow", requires: [try requirement("service.zleaf", ">=1.0.0 <2.0.0")], actions: nil)
        let b = try graphAddon("b", features: [feature])
        let a = try graphAddon("a", dependencies: ["b"])
        for policy in [ResolutionPolicy(maximumDepth: 1), ResolutionPolicy(maximumAddons: 2)] {
            let result = try ResolutionPlanner.resolve(catalog: [a, b, leaf], environment: emptyEnvironment, prior: [], policy: policy)
            #expect(result.blockedFeatures.map(\.featureID) == ["grow"])
            #expect(result.bindings.count == 1)
        }
    }



    @Test func featureCannotGrowDefaultThirtyTwoAddonAncestorClosure() throws {
        let feature = try AddonFeature(id: "grow", requires: [requirement("service.extra", ">=1.0.0 <2.0.0")], actions: nil)
        let middle = try graphAddon("middle", features: [feature])
        let leaves = try (0..<30).map { try graphAddon("leaf\($0)") }
        let ancestor = try graphAddon("ancestor", dependencies: ["middle"] + (0..<30).map { "leaf\($0)" })
        let result = try ResolutionPlanner.resolve(catalog: [ancestor, middle, graphAddon("extra")] + leaves, environment: emptyEnvironment, prior: [])
        #expect(result.acceptedAddons.count == 33)
        #expect(result.blockedFeatures.map(\.featureID) == ["grow"])
        #expect(result.bindings.count == 31)
    }

    @Test func rejectedAnyOfConjunctionReadmitsNestedProvidersCoherently() throws {
        let b = try graphAddon("b", dependencies: ["c"])
        let c = try graphAddon("c")
        let choice = try AddonRequirement(kind: .anyOf, id: nil, version: nil, bundleID: nil, state: nil, anyOf: [
            RequirementAlternative(id: "broken", requires: [requirement("service.b", ">=1.0.0 <2.0.0"), requirement("service.missing", ">=1.0.0 <2.0.0")]),
            RequirementAlternative(id: "working", requires: [requirement("service.c", ">=1.0.0 <2.0.0")])
        ])
        let a = try replacing(graphAddon("a"), requires: [choice])
        let result = try ResolutionPlanner.resolve(catalog: [a, b, c], environment: emptyEnvironment, prior: [])
        #expect(result.bindings.count == 2)
        #expect(result.bindings.first { $0.consumer == b.manifest.id }?.provider == c.manifest.id)
        #expect(result.reverseDependents[b.manifest.id] == nil)
        #expect(result.startOrder.first == c.manifest.id)
    }

    @Test func nestedAnyOfBacktracksSharedBindingAndDoesNotRefundWork() throws {
        let v1 = try graphAddon("v1", service: "shared", version: "1.0.0")
        let v2 = try graphAddon("v2", service: "shared", version: "2.0.0")
        let late = try AddonRequirement(kind: .anyOf, id: nil, version: nil, bundleID: nil, state: nil, anyOf: [
            RequirementAlternative(id: "two", requires: [requirement("service.shared", ">=2.0.0 <3.0.0")])
        ])
        let consumer = try replacing(graphAddon("a"), requires: [requirement("service.shared", ">=1.0.0 <3.0.0"), late])
        let result = try ResolutionPlanner.resolve(catalog: [consumer, v1, v2], environment: emptyEnvironment, prior: [])
        #expect(result.bindings.first?.provider == v2.manifest.id)
        #expect(result.bindings.count == 1)
        #expect(throws: AddonFailure.self) {
            try ResolutionPlanner.resolve(catalog: [consumer, v1, v2], environment: emptyEnvironment, prior: [], policy: ResolutionPolicy(maximumAlternativeSteps: 3))
        }
    }

    @Test func graphRejectedProviderFallsBackToShallowerCandidate() throws {
        let leaf = try graphAddon("leaf")
        let deep = try graphAddon("deep", dependencies: ["leaf"], service: "shared")
        let shallow = try graphAddon("shallow", service: "shared")
        let consumer = try graphAddon("zconsumer", dependencies: ["shared"])
        let result = try ResolutionPlanner.resolve(catalog: [consumer, deep, shallow, leaf], environment: emptyEnvironment, prior: [], policy: ResolutionPolicy(maximumDepth: 1))
        #expect(result.bindings.first { $0.consumer == consumer.manifest.id }?.provider == shallow.manifest.id)
    }


    @Test func blockedPreferredProviderFallsBackToHost() throws {
        let provider = try graphAddon("a-provider", dependencies: ["missing"], service: "shared")
        let consumer = try graphAddon("consumer", dependencies: ["shared"])
        let preferred = ServiceBinding(requirementID: "service.shared", consumer: consumer.manifest.id, provider: provider.manifest.id, providerIdentity: provider.verifiedIdentity, contractVersion: SemanticVersion(1, 0, 0), digest: provider.digest)
        let environment = HostEnvironment(osVersion: emptyEnvironment.osVersion, hostCapabilities: ["service.shared": SemanticVersion(1, 0, 0)], applications: [:], grants: [:], explicitBindings: [preferred])
        let result = try ResolutionPlanner.resolve(catalog: [consumer, provider], environment: environment, prior: [])
        #expect(result.acceptedAddons.contains(consumer.manifest.id))
        #expect(result.bindings.first?.digest == "host")
    }

    @Test func policyCannotRaiseHostCeilings() {
        let policy = ResolutionPolicy(maximumAddons: 1000, maximumEdges: 1000, maximumDepth: 1000, maximumAlternativeSteps: 1000)
        #expect(policy.maximumAddons == 32)
        #expect(policy.maximumEdges == 128)
        #expect(policy.maximumDepth == 8)
        #expect(policy.maximumAlternativeSteps == 256)
    }

    @Test func repeatedServiceConstraintsUseOneCommonBindingOrBlock() throws {
        let base = try installedFixture("focus")
        let v1 = try graphAddon("v1", service: "shared", version: "1.0.0")
        let v2 = try graphAddon("v2", service: "shared", version: "2.0.0")
        for featureScope in [false, true] {
            for overlap in [false, true] {
                let requirements = try [requirement("service.shared", overlap ? ">=1.0.0 <3.0.0" : ">=1.0.0 <2.0.0"), requirement("service.shared", ">=2.0.0 <3.0.0")]
                let feature = try AddonFeature(id: "shared", requires: requirements, actions: nil)
                let consumer = try replacing(base, id: "com.example.a-consumer", requires: featureScope ? [] : requirements, provides: [], features: featureScope ? [feature] : [])
                let result = try ResolutionPlanner.resolve(catalog: [consumer, v1, v2], environment: emptyEnvironment, prior: [])
                let selected = result.bindings.filter { $0.consumer == consumer.manifest.id }
                if overlap {
                    #expect(selected.count == 1)
                    #expect(selected.first?.provider == v2.manifest.id)
                } else {
                    #expect(selected.isEmpty)
                    #expect(featureScope ? result.blockedFeatures.count == 1 : result.blockedAddons.contains { $0.addonID == consumer.manifest.id })
                }
            }
        }
    }

}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}

private func graphAddon(_ name: String, dependencies: [String] = [], service: String? = nil, version: String = "1.0.0", features: [AddonFeature] = []) throws -> InstalledAddon {
    try replacing(installedFixture("focus"), id: "com.example." + name,
                  requires: dependencies.map { try requirement("service." + $0, ">=1.0.0 <2.0.0") },
                  provides: [ProvidedService(kind: .service, id: "service." + (service ?? name), version: version)], features: features)
}
