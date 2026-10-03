//
//  AddonOptionsContractTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeContracts

@Suite
struct AddonOptionsContractTests {

    @Test
    func absentAndFalseFullscreenKeepTheLegacyWireShape() throws {
        let legacy  = Data(#"{"id":"controls","REQUIRES":[],"actions":["open"]}"#.utf8)
        let feature = try JSONDecoder().decode(AddonFeature.self, from: legacy)
        #expect(!feature.supportsFullscreen)
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(feature)) as? [String: Any]
        )
        #expect(object["supportsFullscreen"] == nil)
    }

    @Test
    func fullscreenRoundTripsAndUnknownClaimsAreRejected() throws {
        let feature = try AddonFeature(
            id                : "controls",
            requires          : [],
            actions           : ["open"],
            supportsFullscreen: true
        )
        #expect(
            try JSONDecoder().decode(AddonFeature.self, from: JSONEncoder().encode(feature))
                .supportsFullscreen
        )
        let object = Data(
            #"{"id":"controls","REQUIRES":[],"supportsFullscreen":true,"displayID":10}"#.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AddonFeature.self, from: object)
        }
    }

    @Test
    func optionsOperationRejectsWireOriginAndUnnegotiatedContent() throws {
        let owner    = try #require(AddonID(rawValue: "com.example.options"))
        let source   = PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID())
        let document = try ContentDocument(
            root              : .text("Detail"),
            privacy           : .publicContent,
            accessibilityLabel: "Detail"
        )
        let request = try AddonOptionsRequest(
            publicationID   : source,
            observedRevision: 1,
            actionRequestID : UUID(),
            leaseID         : UUID(),
            document        : document
        )
        let operation = OperationRequest.presentOptions(request)
        #expect(
            try JSONDecoder().decode(OperationRequest.self, from: JSONEncoder().encode(operation))
                == operation
        )
        var fields = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        fields["displayID"] = 10
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                AddonOptionsRequest.self,
                from: JSONSerialization.data(withJSONObject: fields)
            )
        }
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [operation],
            completion   : nil,
            checkpoint   : nil
        )
        #expect(throws: (any Error).self) {
            try output.validateContext(
                authenticatedAddonID: owner,
                expectedCompletion  : nil,
                previousRevisions   : [:]
            )
        }
    }

    @Test
    func oversizedOptionsAreRejectedBeforeDecode() {
        #expect(throws: (any Error).self) {
            try AddonOptionsRequest.decode(Data(repeating: 32, count: 70_000))
        }
    }
}
