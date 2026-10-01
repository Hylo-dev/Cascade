//
//  ResolutionPlanner.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public enum ResolutionPlanner {

    public static func resolve(
        catalog    : [InstalledAddon],
        environment: HostEnvironment,
        prior      : [ServiceBinding],
        policy     : ResolutionPolicy = .init()
    ) throws -> Resolution {
        guard catalog.count <= 1_024 else {
            throw AddonFailure(
                code  : .resolutionTooComplex,
                reason: "Catalog contains \(catalog.count) addons; the bounded catalog limit is 1024."
            )
        }

        let sorted = catalog.sorted { stableKey($0) < stableKey($1) }
        guard Set(sorted.map { $0.manifest.id }).count == sorted.count else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The catalog contains duplicate addon identifiers."
            )
        }

        var state = State(
            catalog    : sorted,
            environment: environment,
            prior      : prior,
            policy     : policy
        )
        for addon in sorted where addon.enabled { _ = try state.admit(addon.manifest.id, stack: []) }
        return state.finish()
    }

    private static func stableKey(_ addon: InstalledAddon) -> String {
        "\(addon.manifest.id.rawValue)\u{0}\(addon.verifiedIdentity.publisher)\u{0}\(addon.manifest.version)\u{0}\(addon.digest)"
    }
}

/// The planner's working types are nested so their short names, State and
/// Outcome among them, stay inside the planner instead of the whole module.
extension ResolutionPlanner {

    private struct State {

        let catalog         : [InstalledAddon]
        let environment     : HostEnvironment
        let prior           : [ServiceBinding]
        let policy          : ResolutionPolicy
        var status          : [AddonID: Visit] = [:]
        var failures        : [AddonID: AddonFailure] = [:]
        var bindings        : [ServiceBinding] = []
        var edges           : Set<Edge> = []
        var order           : [AddonID] = []
        var alternativeSteps = 0

        mutating func admit(
            _ id : AddonID,
            stack: [AddonID]
        ) throws -> Bool {
            guard stack.count <= policy.maximumDepth else {
                return block(
                    id,
                    .resolutionTooComplex,
                    "Dependency depth exceeds \(policy.maximumDepth)."
                )
            }
            if status[id] == .accepted { return true }
            if status[id] == .rejected { return false }
            if status[id] == .visiting {
                return block(
                    id,
                    .dependencyUnavailable,
                    "Dependency cycle: \((stack + [id]).map(\.rawValue).joined(separator: " -> "))."
                )
            }
            guard let addon = catalog.first(where: { $0.manifest.id == id }), addon.enabled else {
                return block(
                    id,
                    .dependencyUnavailable,
                    "Addon \(id.rawValue) is unavailable or disabled."
                )
            }

            let admissionCheckpoint = self
            status[id]              = .visiting

            let requiredPermissions = Set(addon.manifest.permissions.map { $0.id.rawValue })
            guard requiredPermissions.isSubset(of: environment.grants[id, default: []]) else {
                return block(
                    id,
                    .permissionDenied,
                    "Required permission was not granted to \(id.rawValue)."
                )
            }
            guard satisfiesOS(addon.manifest.compatibility.macOS) else {
                return block(
                    id,
                    .versionConflict,
                    "Host OS does not satisfy \(addon.manifest.compatibility.macOS)."
                )
            }

            let wire = addon.manifest.compatibility.cascadeProtocol
            guard wire.major == environment.protocolVersion.major,
                  wire.minimumMinor <= environment.protocolVersion.minor
            else {
                return block(
                    id,
                    .versionConflict,
                    "Host protocol \(environment.protocolVersion.major).\(environment.protocolVersion.minor) does not satisfy \(wire.major).\(wire.minimumMinor)."
                )
            }

            let outcome = try satisfyAll(
                addon.manifest.requires,
                consumer : addon,
                featureID: nil,
                stack    : stack + [id]
            )
            guard outcome.satisfied else {
                restore(admissionCheckpoint)
                return block(
                    id,
                    outcome.code,
                    outcome.reason
                )
            }

            status[id] = .accepted
            if !order.contains(id) { order.append(id) }
            return true
        }

        // Choice points live on the heap: a legal wide conjunction must not consume
        // one Swift call frame per requirement. Only addon dependency admission recurses.
        mutating func satisfyAll(
            _ requirements: [AddonRequirement],
            consumer      : InstalledAddon,
            featureID     : String?,
            stack         : [AddonID]
        ) throws -> Outcome {
            var pending      = requirements
            var choices     : [ChoicePoint] = []
            var backtracking = false
            var last         = Outcome.failure(.missingRequirement, "No alternative is available.")
            while true {
                if backtracking {
                    guard let point = choices.last else { return last }

                    restore(point.checkpoint)
                    guard point.next < point.branches.count else {
                        choices.removeLast()
                        continue
                    }

                    let branch = point.branches[point.next]
                    choices[choices.count - 1].next += 1
                    try spendStep()
                    pending = point.remaining
                    switch branch {
                        case .requirements(let requirements):
                            pending = requirements + pending

                        case .binding(let binding, let isHost):
                            if !isHost {
                                guard try admit(binding.provider, stack: stack) else {
                                    let failure = failures[binding.provider]
                                    last        = .failure(
                                        failure?.code ?? .dependencyUnavailable,
                                        failure?.reason ?? "Provider is unavailable."
                                    )
                                    continue
                                }

                                let edge = Edge(
                                    provider: binding.provider,
                                    consumer: consumer.manifest.id
                                )
                                last     = validateGraph(adding: edge)
                                guard last.satisfied else { continue }

                                edges.insert(edge)
                            }
                            bindings.append(binding)
                    }
                    backtracking = false
                    continue
                }

                guard !pending.isEmpty else { return .success }

                let requirement = pending.removeFirst()
                switch requirement.kind {
                    case .hostCapability:
                        guard let serviceID = requirement.id,
                              let text = requirement.version,
                              let range = SemanticVersionRange(text)
                        else { return .invalid }

                        if let version = environment.hostCapabilities[serviceID] {
                            last = range.contains(version)
                                ? .success
                                : .failure(
                                    .versionConflict,
                                    "Host capability \(serviceID) does not satisfy \(text)."
                                )
                        } else {
                            last = .failure(
                                .missingRequirement,
                                "Host capability \(serviceID) is unavailable."
                            )
                        }

                    case .application:
                        guard let bundleID = requirement.bundleID,
                              let desired = requirement.state
                        else { return .invalid }

                        let availability = environment.applications[bundleID]
                        let present      = desired == .installed
                            ? availability?.installed == true
                            : availability?.running == true
                        last = present
                            ? .success
                            : .failure(
                                .dependencyUnavailable,
                                "Application \(bundleID.rawValue) must be \(desired.rawValue)."
                            )

                    case .service:
                        guard let serviceID = requirement.id,
                              let text = requirement.version,
                              let range = SemanticVersionRange(text)
                        else { return .invalid }

                        if let existing = bindings.first(where: {
                            $0.consumer == consumer.manifest.id
                                && $0.featureID == featureID
                                && $0.requirementID == serviceID
                        }) {
                            last = range.contains(existing.contractVersion)
                                ? .success
                                : .failure(
                                    .versionConflict,
                                    "Conjunctive constraints for \(serviceID) have no compatible shared binding."
                                )
                        } else {
                            let result = serviceChoices(
                                requirement,
                                remaining: pending,
                                consumer : consumer,
                                featureID: featureID
                            )
                            last = result.failure
                            if !result.branches.isEmpty {
                                choices.append(ChoicePoint(
                                    checkpoint: self,
                                    remaining : pending,
                                    branches  : result.branches
                                ))
                            }
                            backtracking = true
                            continue
                        }

                    case .anyOf:
                        let branches = (requirement.anyOf ?? []).map { Branch.requirements($0.requires) }
                        last         = .failure(.missingRequirement, "No alternative is available.")
                        if !branches.isEmpty {
                            choices.append(ChoicePoint(
                                checkpoint: self,
                                remaining : pending,
                                branches  : branches
                            ))
                        }
                        backtracking = true
                        continue
                }
                backtracking = !last.satisfied
            }
        }

        mutating func spendStep() throws {
            alternativeSteps += 1
            guard alternativeSteps <= policy.maximumAlternativeSteps else {
                throw AddonFailure(
                    code  : .resolutionTooComplex,
                    reason: "Resolution search exceeded \(policy.maximumAlternativeSteps) deterministic steps."
                )
            }
        }

        mutating func restore(_ checkpoint: State) {
            let spent        = alternativeSteps
            self             = checkpoint
            alternativeSteps = spent
        }

        func serviceChoices(
            _ requirement: AddonRequirement,
            remaining    : [AddonRequirement],
            consumer     : InstalledAddon,
            featureID    : String?
        ) -> (branches: [Branch], failure: Outcome) {
            guard let serviceID = requirement.id,
                  let rangeText = requirement.version,
                  let range = SemanticVersionRange(rangeText)
            else { return ([], .invalid) }

            let ranges       = [range] + remaining
                .filter { $0.kind == .service && $0.id == serviceID }
                .compactMap { $0.version.flatMap(SemanticVersionRange.init) }
            let allProviding = catalog.filter { addon in addon.manifest.provides.contains { $0.id == serviceID } }
            let candidates   = allProviding.compactMap { addon -> (InstalledAddon, SemanticVersion)? in
                guard addon.enabled,
                      addon.verifiedIdentity.addonID == addon.manifest.id,
                      Set(addon.manifest.permissions.map { $0.id.rawValue })
                        .isSubset(of: environment.grants[addon.manifest.id, default: []]),
                      authorized(
                          consumer : consumer,
                          provider : addon,
                          serviceID: serviceID
                      ),
                      let service = addon.manifest.provides.first(where: { $0.id == serviceID }),
                      let version = SemanticVersion(service.version),
                      ranges.allSatisfy({ $0.contains(version) })
                else { return nil }

                return (addon, version)
            }

            let allPreferred = environment.explicitBindings + prior
            let preferred    = allPreferred.filter { $0.featureID == featureID }
                + (featureID == nil ? [] : allPreferred.filter { $0.featureID == nil })
            var choices: [ServiceBinding] = []

            func binding(for candidate: (InstalledAddon, SemanticVersion)) -> ServiceBinding {
                ServiceBinding(
                    requirementID   : serviceID,
                    consumer        : consumer.manifest.id,
                    provider        : candidate.0.manifest.id,
                    providerIdentity: candidate.0.verifiedIdentity,
                    contractVersion : candidate.1,
                    digest          : candidate.0.digest,
                    featureID       : featureID
                )
            }

            for preference in preferred
                where preference.consumer == consumer.manifest.id && preference.requirementID == serviceID {
                if let match = candidates.first(where: {
                    $0.0.manifest.id == preference.provider
                        && $0.0.verifiedIdentity == preference.providerIdentity
                        && $0.0.digest == preference.digest
                        && $0.1 == preference.contractVersion
                }) {
                    let choice = binding(for: match)
                    if !choices.contains(choice) { choices.append(choice) }
                }
            }

            let hostID       = AddonID(rawValue: "app.cascade.host")!
            let hostIdentity = VerifiedAddonIdentity(publisher: "cascade.host", addonID: hostID)
            let hostChoice   = environment.hostCapabilities[serviceID].flatMap { version -> ServiceBinding? in
                guard ranges.allSatisfy({ $0.contains(version) }) else { return nil }

                return ServiceBinding(
                    requirementID   : serviceID,
                    consumer        : consumer.manifest.id,
                    provider        : hostID,
                    providerIdentity: hostIdentity,
                    contractVersion : version,
                    digest          : "host",
                    featureID       : featureID
                )
            }
            if let hostChoice { choices.append(hostChoice) }
            for candidate in candidates {
                let choice = binding(for: candidate)
                if !choices.contains(choice) { choices.append(choice) }
            }

            guard !choices.isEmpty else {
                let incompatible = allProviding.contains { addon in
                    addon.manifest.provides.contains { service in
                        service.id == serviceID && SemanticVersion(service.version).map { version in
                            !ranges.allSatisfy { $0.contains(version) }
                        } == true
                    }
                }
                let code: AddonFailure.Code = allProviding.isEmpty
                    ? .missingRequirement
                    : (incompatible ? .versionConflict : .dependencyUnavailable)
                return (
                    [],
                    .failure(
                        code,
                        "No enabled, authorized provider satisfies every constraint for \(serviceID)."
                    )
                )
            }

            return (
                choices.map { .binding($0, isHost: $0 == hostChoice) },
                .failure(
                    .dependencyUnavailable,
                    "All compatible providers for \(serviceID) are blocked."
                )
            )
        }

        func authorized(
            consumer : InstalledAddon,
            provider : InstalledAddon,
            serviceID: String
        ) -> Bool {
            if consumer.verifiedIdentity.publisher == provider.verifiedIdentity.publisher { return true }

            let grant = ServiceAccessGrant(
                consumer        : consumer.manifest.id,
                requirementID   : serviceID,
                providerIdentity: provider.verifiedIdentity
            )
            return environment.serviceAccessGrants.contains(grant)
        }

        mutating func finish() -> Resolution {
            let accepted        = order.sorted { $0.rawValue < $1.rawValue }
            var enabledFeatures: [ResolvedFeature] = []
            var blockedFeatures: [BlockedFeature] = []
            for addon in catalog where status[addon.manifest.id] == .accepted {
                for feature in addon.manifest.features.sorted(by: { $0.id < $1.id }) {
                    let checkpoint = self
                    var failure   : AddonFailure?
                    do {
                        let outcome = try satisfyAll(
                            feature.requires,
                            consumer : addon,
                            featureID: feature.id,
                            stack    : [addon.manifest.id]
                        )
                        if !outcome.satisfied {
                            failure = AddonFailure(code: outcome.code, reason: outcome.reason)
                        }
                    } catch let error as AddonFailure {
                        failure = error
                    } catch {
                        failure = AddonFailure(
                            code  : .dependencyUnavailable,
                            reason: error.localizedDescription
                        )
                    }

                    if let failure {
                        restore(checkpoint)
                        blockedFeatures.append(.init(
                            addonID  : addon.manifest.id,
                            featureID: feature.id,
                            failure  : failure
                        ))
                    } else {
                        enabledFeatures.append(.init(
                            addonID  : addon.manifest.id,
                            featureID: feature.id
                        ))
                    }
                }
            }

            var reverse: [AddonID: [AddonID]] = [:]
            for edge in edges { reverse[edge.provider, default: []].append(edge.consumer) }
            for key in reverse.keys { reverse[key]?.sort { $0.rawValue < $1.rawValue } }

            return Resolution(
                acceptedAddons   : accepted,
                blockedAddons    : failures
                    .map { .init(addonID: $0.key, failure: $0.value) }
                    .sorted { $0.addonID.rawValue < $1.addonID.rawValue },
                enabledFeatures  : enabledFeatures.sorted(by: featureOrder),
                blockedFeatures  : blockedFeatures.sorted(by: blockedFeatureOrder),
                startOrder       : topologicalOrder(accepted),
                bindings         : bindings.sorted(by: bindingOrder),
                reverseDependents: reverse
            )
        }

        mutating func block(
            _ id    : AddonID,
            _ code  : AddonFailure.Code,
            _ reason: String
        ) -> Bool {
            status[id]   = .rejected
            failures[id] = AddonFailure(code: code, reason: reason)
            return false
        }

        func satisfiesOS(_ text: String) -> Bool {
            guard text.hasPrefix(">="),
                  let minimum = SemanticVersion(String(text.dropFirst(2)) + ".0")
            else { return false }

            return environment.osVersion >= minimum
        }

        func topologicalOrder(_ accepted: [AddonID]) -> [AddonID] {
            var result   : [AddonID] = []
            var remaining = Set(accepted)
            while !remaining.isEmpty {
                let ready = remaining.filter { id in
                    !edges.contains { $0.consumer == id && remaining.contains($0.provider) }
                }.sorted { $0.rawValue < $1.rawValue }
                guard !ready.isEmpty else { return order }

                result += ready
                remaining.subtract(ready)
            }

            return result
        }

        // Validate the resulting graph, including ancestors whose already accepted
        // closure grows through this edge. Memoization bounds shared DAG traversal.
        func validateGraph(adding edge: Edge) -> Outcome {
            let graph = edges.union([edge])
            guard graph.count <= policy.maximumEdges else {
                return .failure(
                    .resolutionTooComplex,
                    "Dependency graph exceeds \(policy.maximumEdges) edges."
                )
            }

            var dependencies: [AddonID: [AddonID]] = [:]
            var nodes       : Set<AddonID> = []
            for edge in graph {
                dependencies[edge.consumer, default: []].append(edge.provider)
                nodes.formUnion([edge.consumer, edge.provider])
            }
            for node in dependencies.keys { dependencies[node]?.sort { $0.rawValue < $1.rawValue } }

            var closures: [AddonID: Set<AddonID>] = [:]
            var depths  : [AddonID: Int] = [:]
            func visit(
                _ node: AddonID,
                path  : [AddonID]
            ) -> Outcome {
                if let index = path.firstIndex(of: node) {
                    return .failure(
                        .dependencyUnavailable,
                        "Dependency cycle: \((Array(path[index...]) + [node]).map(\.rawValue).joined(separator: " -> "))."
                    )
                }
                if closures[node] != nil { return .success }

                var closure: Set<AddonID> = [node]
                var depth   = 0
                for provider in dependencies[node, default: []] {
                    let outcome = visit(provider, path: path + [node])
                    if !outcome.satisfied { return outcome }
                    closure.formUnion(closures[provider, default: []])
                    depth = max(depth, 1 + depths[provider, default: 0])
                }

                guard closure.count <= policy.maximumAddons else {
                    return .failure(
                        .resolutionTooComplex,
                        "Dependency closure exceeds \(policy.maximumAddons) addons."
                    )
                }
                guard depth <= policy.maximumDepth else {
                    return .failure(
                        .resolutionTooComplex,
                        "Dependency depth exceeds \(policy.maximumDepth)."
                    )
                }

                closures[node] = closure
                depths[node]   = depth
                return .success
            }
            for node in nodes.sorted(by: { $0.rawValue < $1.rawValue }) {
                let outcome = visit(node, path: [])
                if !outcome.satisfied { return outcome }
            }

            return .success
        }
    }

    private enum Visit {

        case visiting
        case accepted
        case rejected
    }

    private struct Edge: Hashable {

        let provider: AddonID
        let consumer: AddonID
    }

    private struct Outcome {

        let satisfied: Bool
        let code     : AddonFailure.Code
        let reason   : String

        static let success = Outcome(
            satisfied: true,
            code     : .missingRequirement,
            reason   : ""
        )
        static let invalid = Outcome.failure(.invalidPayload, "Requirement is malformed.")

        static func failure(
            _ code  : AddonFailure.Code,
            _ reason: String
        ) -> Outcome {
            .init(
                satisfied: false,
                code     : code,
                reason   : reason
            )
        }
    }

    private enum Branch {

        case requirements([AddonRequirement])
        case binding     (ServiceBinding, isHost: Bool)
    }

    private struct ChoicePoint {

        let checkpoint: State
        let remaining : [AddonRequirement]
        let branches  : [Branch]
        var next       = 0
    }
}

private func featureOrder(
    _ lhs: ResolvedFeature,
    _ rhs: ResolvedFeature
) -> Bool {
    (lhs.addonID.rawValue, lhs.featureID) < (rhs.addonID.rawValue, rhs.featureID)
}

private func blockedFeatureOrder(
    _ lhs: BlockedFeature,
    _ rhs: BlockedFeature
) -> Bool {
    (lhs.addonID.rawValue, lhs.featureID) < (rhs.addonID.rawValue, rhs.featureID)
}

private func bindingOrder(
    _ lhs: ServiceBinding,
    _ rhs: ServiceBinding
) -> Bool {
    (lhs.consumer.rawValue, lhs.featureID ?? "", lhs.requirementID, lhs.provider.rawValue)
        < (rhs.consumer.rawValue, rhs.featureID ?? "", rhs.requirementID, rhs.provider.rawValue)
}
