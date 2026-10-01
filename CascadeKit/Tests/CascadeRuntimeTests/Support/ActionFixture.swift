//
//  ActionFixture.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// ActionFixture uses real validated contracts and a deterministic civil clock.
struct ActionFixture {

    let wall          = Date(timeIntervalSince1970: 2_000_000_000)
    let owner        : AddonID
    let publicationID: PublicationID

    init(ownerName: String = "com.example.actions") throws {
        owner         = try #require(AddonID(rawValue: ownerName))
        publicationID = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
    }

    func request(
        id      : UUID = UUID(),
        input   : Data = Data([7]),
        revision: UInt64 = 1
    ) throws -> ActionRequest {
        try ActionRequest(
            schemaVersion   : 1,
            requestID       : id,
            publicationID   : publicationID,
            actionID        : "pause",
            input           : input,
            deadline        : wall.addingTimeInterval(20),
            observedRevision: revision
        )
    }

    func presentation(
        payload     : Data = Data([7]),
        action      : String = "pause",
        otherPayload: Data? = nil
    ) throws -> PresentationSet {
        func document(_ payload: Data) throws -> ContentDocument {
            try ContentDocument(
                root: .column([.row([.action(ActionDescriptor(
                    id     : action,
                    label  : "Pause",
                    payload: payload
                ))])]),
                privacy           : .publicContent,
                accessibilityLabel: "Controls"
            )
        }

        return try PresentationSet(
            widget         : document(payload),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : otherPayload.map { try document($0) }
        )
    }

    func context(
        revision      : UInt64 = 1,
        payload       : Data = Data([7]),
        action        : String = "pause",
        declarations  : [String]? = ["pause"],
        feature       : String = "controls",
        blockedRoot   : Bool = false,
        blockedFeature: String? = nil,
        enabled       : Bool = true,
        eligibility   : ActionAuthorizer.Eligibility = .available,
        digest        : String = "artifact-a",
        publisher     : String = "verified.publisher",
        timeline      : [ScheduledEntry]? = nil,
        otherPayload  : Data? = nil
    ) throws -> ActionAuthorizer.Context {
        let data = Data("""
        {"manifestVersion":1,"id":"\(owner.rawValue)","version":"1.0.0",
        "compatibility":{"macOS":">=14.0","cascadeProtocol":{"major":1,"minimumMinor":0}},
        "execution":{"owner":"cascade","activation":"onDemand","entryPoint":"provider"},
        "bundledLibraries":[],"REQUIRES":[],"PROVIDES":[],"features":[],"permissions":[],
        "resources":{"profile":"eventDriven","requestedMemoryMiB":32,"maximumConcurrentWork":1,"background":"none"}}
        """.utf8)
        let base     = try JSONDecoder().decode(AddonManifest.self, from: data)
        let manifest = try AddonManifest(
            manifestVersion : 1,
            id              : owner,
            version         : base.version,
            compatibility   : base.compatibility,
            execution       : base.execution,
            sourceApp       : nil,
            bundledLibraries: [],
            requires        : [],
            provides        : [],
            features        : [
                AddonFeature(
                    id      : "controls",
                    requires: [],
                    actions : declarations
                ),
                AddonFeature(
                    id      : "other",
                    requires: [],
                    actions : declarations
                )
            ],
            permissions: [],
            resources  : base.resources
        )
        let failure    = AddonFailure(code: .permissionDenied, reason: "Denied")
        let resolution = Resolution(
            acceptedAddons : [owner],
            blockedAddons  : blockedRoot ? [BlockedAddon(addonID: owner, failure: failure)] : [],
            enabledFeatures: [
                ResolvedFeature(addonID: owner, featureID: "controls"),
                ResolvedFeature(addonID: owner, featureID: "other")
            ],
            blockedFeatures: blockedFeature.map {
                [BlockedFeature(
                    addonID  : owner,
                    featureID: $0,
                    failure  : failure
                )]
            } ?? [],
            startOrder       : [owner],
            bindings         : [],
            reverseDependents: [:]
        )
        let installed = try InstalledAddon(
            manifest        : manifest,
            verifiedIdentity: VerifiedAddonIdentity(publisher: publisher, addonID: owner),
            digest          : digest,
            enabled         : enabled
        )

        return try ActionAuthorizer.Context(
            installed  : installed,
            resolution : resolution,
            featureID  : feature,
            publication: Publication(
                id      : publicationID,
                revision: revision,
                kind    : .widget,
                content : timeline == nil
                    ? presentation(
                        payload     : payload,
                        action      : action,
                        otherPayload: otherPayload
                    ) : nil,
                timeline   : timeline,
                expiresAt  : wall.addingTimeInterval(100),
                stalePolicy: .retainMarked
            ),
            eligibility: eligibility
        )
    }
}
