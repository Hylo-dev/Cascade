//
//  MessageTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

private let requestID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()

func documentObject(text: String = "Focus") -> [String: Any] {
    [
        "schemaVersion": 1, "root": ["kind": "text", "text": text], "accessibilityLabel": "Focus timer",
        "privacy": "public", "assets": [],
    ]
}

func publicationObject() -> [String: Any] {
    [
        "id": [
            "addonID": "com.example.focus.cascade", "instanceID": UUID().uuidString, "sessionID": UUID().uuidString,
        ], "revision": 1, "kind": "widget", "content": ["widget": documentObject()], "expiresAt": 1000,
        "stalePolicy": "retainMarked",
    ]
}

func outputData(publications: [[String: Any]] = [], operations: [[String: Any]] = [], checkpoint: Data? = nil) throws
    -> Data
{
    var object: [String: Any] = ["schemaVersion": 1, "publications": publications, "operations": operations]
    if let checkpoint { object["checkpoint"] = checkpoint.base64EncodedString() }
    return try JSONSerialization.data(withJSONObject: object)
}

@Suite struct MessageTests {
    @Test func rejectsEnvelopeBeforeParsingAndChecksLists() throws {
        let valid = try outputData()
        #expect(throws: (any Error).self) { try ProviderOutput.decode(valid + Data(repeating: 32, count: 524_289)) }
        #expect(throws: (any Error).self) {
            try ProviderOutput.decode(outputData(publications: (0..<17).map { _ in publicationObject() }))
        }
        let operation: [String: Any] = ["kind": "schedule", "deadline": 200, "eventID": "timer"]
        #expect(throws: (any Error).self) {
            try ProviderOutput.decode(outputData(operations: Array(repeating: operation, count: 17)))
        }
        #expect(throws: (any Error).self) {
            try ProviderOutput.decode(outputData(checkpoint: Data(repeating: 0, count: 65_537)))
        }
    }

    @Test func rejectsUncorrelatedActionAndServiceResults() throws {
        let addon = try #require(AddonID(rawValue: "com.example.focus.cascade"))
        let action = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations: [],
            completion: .action(requestID: requestID, outcome: .outcomeUnknown),
            checkpoint: nil
        )
        #expect(throws: (any Error).self) {
            try action.validateContext(
                authenticatedAddonID: addon,
                expectedCompletion: .action(requestID: UUID()),
                previousRevisions: [:]
            )
        }
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID: "com.example.timer",
            operation: "read",
            payload: Data()
        )
        let service = try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations: [],
            completion: .service(requestID: requestID, response: response),
            checkpoint: nil
        )
        #expect(throws: (any Error).self) {
            try service.validateContext(
                authenticatedAddonID: addon,
                expectedCompletion: .action(requestID: requestID),
                previousRevisions: [:]
            )
        }
        #expect(throws: (any Error).self) {
            try service.validateContext(
                authenticatedAddonID: addon,
                expectedCompletion: .service(requestID: UUID(), contractID: "com.example.timer", operation: "read"),
                previousRevisions: [:]
            )
        }
        #expect(throws: (any Error).self) {
            try service.validateContext(
                authenticatedAddonID: addon,
                expectedCompletion: .service(requestID: requestID, contractID: "com.example.other", operation: "read"),
                previousRevisions: [:]
            )
        }
    }

    @Test func rejectsReplayedRevisionAndSourceBundleAsOwner() throws {
        let output = try ProviderOutput.decode(outputData(publications: [publicationObject()]))
        let publication = try #require(output.publications.first)
        let sourceApp = try #require(AddonID(rawValue: "com.example.focus"))
        #expect(throws: (any Error).self) {
            try output.validateContext(authenticatedAddonID: sourceApp, expectedCompletion: nil, previousRevisions: [:])
        }
        #expect(throws: (any Error).self) {
            try output.validateContext(
                authenticatedAddonID: publication.id.addonID,
                expectedCompletion: nil,
                previousRevisions: [publication.id: 1]
            )
        }
    }

    @Test(arguments: [
        "both", "missing", "noticeExpanded", "activityMissing", "text", "depth", "nodes", "duplicateActions",
        "timeline",
    ])
    func rejectsInvalidPublications(_ mutation: String) throws {
        var publication = publicationObject()
        switch mutation {
        case "both": publication["timeline"] = [["date": 10, "content": ["widget": documentObject()]]]
        case "missing": publication.removeValue(forKey: "content")
        case "noticeExpanded":
            publication["kind"] = "notice"
            publication["content"] = [
                "compactLeading": documentObject(), "compactTrailing": documentObject(), "minimal": documentObject(),
                "expanded": documentObject(),
            ]
        case "activityMissing": publication["kind"] = "activity"
        case "text": publication["content"] = ["widget": documentObject(text: String(repeating: "a", count: 4097))]
        case "depth", "nodes", "duplicateActions":
            var document = documentObject()
            var node: [String: Any] = ["kind": "text", "text": "Leaf"]
            if mutation == "depth" { for _ in 0..<8 { node = ["kind": "row", "children": [node]] } }
            if mutation == "nodes" { node = ["kind": "row", "children": Array(repeating: node, count: 128)] }
            if mutation == "duplicateActions" {
                node = [
                    "kind": "row",
                    "children": Array(repeating: ["kind": "action", "actionID": "pause", "text": "Pause"], count: 2),
                ]
            }
            document["root"] = node
            publication["content"] = ["widget": document]
        default:
            publication.removeValue(forKey: "content")
            publication["timeline"] = (0..<33).map { ["date": $0, "content": ["widget": documentObject()]] }
        }
        #expect(throws: (any Error).self) { try ProviderOutput.decode(outputData(publications: [publication])) }
    }

    @Test func rejectsSecurityScopeExtensions() throws {
        let operation: [String: Any] = [
            "kind": "requestService", "requirementID": "timer",
            "scope": ["featureID": "localTimer", "operation": "read", "allFiles": true],
        ]
        #expect(throws: (any Error).self) { try ProviderOutput.decode(outputData(operations: [operation])) }
    }

    @Test func enforcesCombinedRepresentationAndEnvelopeBytes() throws {
        var document = documentObject()
        document["root"] = [
            "kind": "row",
            "children": (0..<10).map { _ in ["kind": "text", "text": String(repeating: "a", count: 4000)] },
        ]
        var publication = publicationObject()
        publication["content"] = ["widget": document, "expanded": document]
        #expect(throws: (any Error).self) { try ProviderOutput.decode(outputData(publications: [publication])) }
        let publications = (0..<14).map { _ -> [String: Any] in
            var item = publicationObject()
            item["content"] = ["widget": document]
            return item
        }
        let encoded = try outputData(publications: publications)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ProviderOutput.self, from: encoded) }
    }

    @Test func roundTripsAndPublicationDoesNotImplyCompletion() throws {
        let output = try ProviderOutput.decode(outputData(publications: [publicationObject()]))
        #expect(output.completion == nil)
        let restored = try JSONDecoder().decode(ProviderOutput.self, from: JSONEncoder().encode(output))
        #expect(restored == output)
        let completion = InvocationCompletion.action(requestID: requestID, outcome: .completed(payload: Data([1, 2])))
        #expect(
            try JSONDecoder().decode(InvocationCompletion.self, from: JSONEncoder().encode(completion)) == completion
        )
    }
    @Test func directDecodersCannotBypassPayloadLimits() throws {
        let outcome = ActionOutcome.completed(payload: Data(repeating: 0, count: 65_537))
        let encoded = try JSONEncoder().encode(outcome)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ActionOutcome.self, from: encoded) }
        let action: [String: Any] = [
            "schemaVersion": 1, "requestID": requestID.uuidString, "publicationID": publicationObject()["id"] as Any,
            "actionID": "pause", "input": Data(repeating: 0, count: 4097).base64EncodedString(), "deadline": 300,
            "observedRevision": 1,
        ]
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ActionRequest.self, from: JSONSerialization.data(withJSONObject: action))
        }
        let set: [String: Any] = ["widget": documentObject(), "arbitrarySurface": documentObject()]
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PresentationSet.self, from: JSONSerialization.data(withJSONObject: set))
        }
    }

    @Test func validatesOperationsBuiltInSwift() throws {
        #expect(throws: (any Error).self) {
            try ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations: [.schedule(deadline: Date(), eventID: "")],
                completion: nil,
                checkpoint: nil
            )
        }
    }

    @Test func countsTimelineBytesAcrossAllEntries() throws {
        var document = documentObject()
        document["root"] = [
            "kind": "row",
            "children": (0..<10).map { _ in ["kind": "text", "text": String(repeating: "a", count: 4000)] },
        ]
        var publication = publicationObject()
        publication.removeValue(forKey: "content")
        publication["timeline"] = (0..<7).map { ["date": $0, "content": ["widget": document]] }
        #expect(throws: (any Error).self) { try ProviderOutput.decode(outputData(publications: [publication])) }
    }

    @Test func rejectsInvalidGrantAndLeaseDeadlines() throws {
        let addon = try #require(AddonID(rawValue: "com.example.focus.cascade"))
        let scope = try ServiceScope(featureID: "localTimer", operation: "read")
        let cost = try AddonResourceRequest(
            profile: .eventDriven,
            requestedMemoryMiB: 32,
            maximumConcurrentWork: 1,
            background: .scheduledDeadline
        )
        #expect(throws: (any Error).self) {
            try Grant(
                id: UUID(),
                owner: addon,
                serviceID: "",
                scope: scope,
                expiresAt: Date(),
                generation: ConnectionGeneration(),
                cost: cost
            )
        }
        let grant = try Grant(
            id: UUID(),
            owner: addon,
            serviceID: "com.example.timer",
            scope: scope,
            expiresAt: Date(),
            generation: ConnectionGeneration(),
            cost: cost
        )
        #expect(throws: (any Error).self) { try Lease(id: UUID(), grant: grant, monotonicDeadlineNanoseconds: 0) }
        let lease = try Lease(id: UUID(), grant: grant, monotonicDeadlineNanoseconds: 1000)
        #expect(try JSONDecoder().decode(Lease.self, from: JSONEncoder().encode(lease)) == lease)
    }

    @Test func roundTripsAllOperationKindsAndTimelineAtEntryLimit() throws {
        let scope = try ServiceScope(featureID: "timer", operation: "read")
        let output = try ProviderOutput.decode(outputData(publications: [publicationObject()]))
        let id = try #require(output.publications.first?.id)
        let operations: [OperationRequest] = [
            .requestService(requirementID: "com.example.timer", scope: scope),
            .schedule(deadline: Date(timeIntervalSinceReferenceDate: 5), eventID: "timer"),
            .releaseLease(leaseID: requestID),
            .endPublication(id),
        ]
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID: "com.example.timer",
            operation: "read",
            payload: Data([1])
        )
        let message = try ProviderOutput(
            schemaVersion: 1,
            publications: output.publications,
            operations: operations,
            completion: .service(requestID: requestID, response: response),
            checkpoint: Data([2])
        )
        let restored = try ProviderOutput.decode(JSONEncoder().encode(message))
        #expect(restored == message)
        try restored.validateContext(
            authenticatedAddonID: id.addonID,
            expectedCompletion: .service(requestID: requestID, contractID: "com.example.timer", operation: "read"),
            previousRevisions: [id: 0]
        )
        var timeline = publicationObject()
        timeline.removeValue(forKey: "content")
        timeline["timeline"] = (0..<32).map { ["date": $0, "content": ["widget": documentObject()]] }
        #expect(
            try ProviderOutput.decode(outputData(publications: [timeline])).publications.first?.timeline?.count == 32
        )
    }

    @Test func rejectsUnknownWireDiscriminantsAndNonFiniteDates() throws {
        #expect(throws: (any Error).self) {
            try ProviderOutput.decode(outputData(operations: [["kind": "shell", "command": "anything"]]))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ActionOutcome.self, from: Data("{\"accepted\":{}}".utf8))
        }
        let encoded = try outputData(operations: [["kind": "schedule", "deadline": "NaN", "eventID": "timer"]])
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        #expect(throws: (any Error).self) { try decoder.decode(ProviderOutput.self, from: encoded) }
    }

    @Test func rejectsExtraFieldsInsideMessageDiscriminators() throws {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ActionOutcome.self, from: Data("{\"outcomeUnknown\":{\"accepted\":true}}".utf8))
        }
        #expect(throws: (any Error).self) {
            try ProviderOutput.decode(
                outputData(operations: [
                    ["kind": "schedule", "deadline": 10, "eventID": "timer", "leaseID": requestID.uuidString]
                ])
            )
        }
        let object: [String: Any] = [
            "action": ["requestID": requestID.uuidString, "outcome": ["outcomeUnknown": [:]], "grant": "untrusted"]
        ]
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(InvocationCompletion.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func boundsSwiftFailureReasonsByUTF8AndRoundTripsRejections() throws {
        // This byte fixture is independent of the production truncation algorithm:
        // 4,096 ASCII bytes are permitted, while one combining cluster can exceed it.
        let byteBoundary = String(decoding: Data(repeating: 0x61, count: 4096), as: UTF8.self)
        let combiningCluster = "e" + String(repeating: "\u{0301}", count: 4096)
        let reasons = ["", String(repeating: "👨‍👩‍👧‍👦", count: 1024), combiningCluster, byteBoundary]
        for reason in reasons {
            let failure = AddonFailure(code: .permissionDenied, reason: reason)
            #expect(!failure.reason.isEmpty)
            #expect(failure.reason.utf8.count <= 4096)
            let output = try ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations: [],
                completion: .action(requestID: requestID, outcome: .rejected(reason: failure)),
                checkpoint: nil
            )
            #expect(throws: Never.self) { () throws -> Void in
                #expect(try ProviderOutput.decode(JSONEncoder().encode(output)) == output)
            }
        }
        #expect(AddonFailure(code: .permissionDenied, reason: byteBoundary).reason == byteBoundary)
        let familyReason = AddonFailure(code: .permissionDenied, reason: String(repeating: "👨‍👩‍👧‍👦", count: 1024))
        #expect(familyReason.reason == String(repeating: "👨‍👩‍👧‍👦", count: 163))
    }

    @Test func rejectsUntrustedFailureReasonBytesInsteadOfNormalizingWireData() throws {
        // The payload is assembled from independent literal bytes, not an SDK encoder.
        let prefix = Data("{\"code\":\"permissionDenied\",\"reason\":\"".utf8)
        let suffix = Data("\"}".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AddonFailure.self, from: prefix + Data(repeating: 0x61, count: 4097) + suffix)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AddonFailure.self, from: prefix + suffix)
        }
        let accepted = try JSONDecoder().decode(
            AddonFailure.self,
            from: prefix + Data(repeating: 0x61, count: 4096) + suffix
        )
        #expect(accepted.reason.utf8.count == 4096)
    }

}
