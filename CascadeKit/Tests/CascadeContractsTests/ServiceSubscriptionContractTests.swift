//
//  ServiceSubscriptionContractTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

/// ServiceSubscriptionContractTests covers pure syntax only. No broker, readiness, SDK dispatch
/// or allocator claims.
@Suite
struct ServiceSubscriptionContractTests {

    private let id    = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let maxID = String(repeating: "a", count: 128)

    private func scope(
        _ feature  : String = "feature",
        _ operation: String = "read"
    ) throws -> ServiceScope {
        try ServiceScope(featureID: feature, operation: operation)
    }

    private func grant(
        maximum  : Bool = false,
        feature  : String = "feature",
        operation: String = "read"
    ) throws -> Grant {
        try Grant(
            id        : other,
            owner     : AddonID(rawValue: maximum ? "a." + String(repeating: "a", count: 253) : "test.owner")!,
            serviceID : maximum ? maxID : "contract",
            scope     : scope(maximum ? maxID : feature, maximum ? maxID : operation),
            expiresAt : Date(timeIntervalSinceReferenceDate: 1.7976931348623155e308),
            generation: ConnectionGeneration(value: id),
            cost      : AddonResourceRequest(
                profile              : .eventDriven,
                requestedMemoryMiB   : 64,
                maximumConcurrentWork: 1,
                background           : .scheduledDeadline
            )
        )
    }

    private func response(
        _ payload: Data = Data(),
        maximum  : Bool = false,
        contract : String = "contract",
        operation: String = "read"
    ) throws -> ServiceResponse {
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : maximum ? maxID : contract,
            operation    : maximum ? maxID : operation,
            payload      : payload
        )
    }

    private func start(maximum: Bool = false) throws -> ServiceSourceStartFrame {
        try ServiceSourceStartFrame(
            sourceID       : id,
            startNonce     : other,
            providerID     : grant(maximum: maximum).owner,
            publisher      : maximum ? String(repeating: "\u{01}", count: 256) : "publisher",
            digest         : maximum ? String(repeating: "\u{01}", count: 512) : "digest",
            contractVersion: maximum ? "1.2.3+" + String(repeating: "a", count: 122) : "1.2.3-beta.1+build.9",
            serviceID      : maximum ? maxID : "contract",
            partition      : maximum ? String(repeating: "\u{01}", count: 256) : "partition",
            scope          : scope(maximum ? maxID : "feature", maximum ? maxID : "read")
        )
    }

    private func request(
        _ action: ServiceControlAction = .acquire(.requestService(
            requirementID: "binding",
            scope        : try! ServiceScope(featureID: "feature", operation: "read")
        ))
    ) throws -> ServiceControlRequest {
        try ServiceControlRequest(requestID: id, action: action)
    }

    private func reply(
        _ kind  : ServiceControlKind = .acquire,
        _ phase : ServiceControlPhase = .terminal,
        _ result: ServiceControlResult
    ) throws -> ServiceControlReply {
        try ServiceControlReply(
            requestID: id,
            kind     : kind,
            phase    : phase,
            result   : result
        )
    }

    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ value: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

    private func decode(
        _ data   : Data,
        _ family : Int,
        _ profile: ServiceSubscriptionFrameProfile? = .v1_4
    ) throws {
        switch family {
            case 0: _ = try ServiceSubscriptionFrameCodec.decodeControlRequest(data, profile: profile)
            case 1: _ = try ServiceSubscriptionFrameCodec.decodeControlReply(data, profile: profile)
            case 2: _ = try ServiceSubscriptionFrameCodec.decodeSourceStart(data, profile: profile)
            case 3: _ = try ServiceSubscriptionFrameCodec.decodeSourceOutput(data, profile: profile)
            default: _ = try ServiceSubscriptionFrameCodec.decodeServiceEvent(data, profile: profile)
        }
    }

    private func slashEscaped(_ data: Data) -> Data {
        Data(
            String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "/", with: "\\/")
                .utf8
        )
    }

    private func semantic(
        _ code: AddonFailure.Code,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            Issue.record("Expected semantic rejection \(code)")
        } catch let failure as AddonFailure {
            #expect(failure.code == code)
        } catch {
            Issue.record("Expected AddonFailure; got \(error)")
        }
    }

    // Removing closed acquire support must break this behavioral acceptance check.
    @Test
    func acquireClosedRequestDecodes() {
        let bytes = Data(#"{"schemaVersion":1,"requestID":"00000000-0000-0000-0000-000000000001","kind":"acquire","operation":{"kind":"requestService","requirementID":"binding","scope":{"featureID":"feature","operation":"read"}}}"#.utf8)

        #expect(throws: Never.self) { _ = try ServiceSubscriptionFrameCodec.decodeControlRequest(bytes, profile: .v1_4) }
    }

    @Test
    func requestCasesRoundtripExactKeysAndRestrictedOperation() throws {
        let cases: [(ServiceControlAction, Set<String>, String)] = [
            (.acquire(.requestService(requirementID: "binding", scope: try scope())), ["operation"], "acquire"),
            (.subscribe(requirementID: "binding", grantID: other), ["requirementID", "grantID"], "subscribe"),
            (.unsubscribe(subscriptionID: other), ["subscriptionID"], "unsubscribe")
        ]

        for (action, fields, wireKind) in cases {
            let value = try request(action)
            let data  = try ServiceSubscriptionFrameCodec.encode(value, profile: .v1_4)

            #expect(try ServiceSubscriptionFrameCodec.decodeControlRequest(data, profile: .v1_4) == value)
            #expect(try JSONDecoder().decode(ServiceControlRequest.self, from: encoded(value)) == value)
            #expect(try object(data)["kind"] as? String == wireKind)
            #expect(Set(try object(data).keys) == fields.union(["schemaVersion", "requestID", "kind"]))
        }

        for operation in [
            OperationRequest.schedule(deadline: Date(), eventID: "event"),
            .releaseLease(leaseID: other),
            .endPublication(PublicationID(addonID: try grant().owner, instanceID: id, sessionID: other))
        ] {
            #expect(throws: (any Error).self) { try request(.acquire(operation)) }

            var fields = try object(encoded(request()))
            fields["operation"] = try object(encoded(operation))
            #expect(throws: (any Error).self) { try decode(json(fields), 0) }
        }

        for binding in ["", maxID + "a", "bad space"] {
            #expect(throws: (any Error).self) { try request(.subscribe(requirementID: binding, grantID: other)) }
        }
    }

    @Test
    func allLegalRepliesAndEveryPhaseKindResultCombination() throws {
        let results: [ServiceControlResult] = [
            .accepted, .acquired(try grant()), .subscribed(other), .acknowledged,
            .refused(code: .permissionDenied, reason: "Denied"), .outcomeUnknown
        ]

        for kind in [ServiceControlKind.acquire, .subscribe, .unsubscribe] {
            for phase in [ServiceControlPhase.admission, .terminal] {
                for (index, result) in results.enumerated() {
                    let legal = phase == .admission ? kind == .acquire && index == 0 :
                        index >= 4
                            || (kind == .acquire && index == 1)
                            || (kind == .subscribe && index == 2)
                            || (kind == .unsubscribe && index == 3)
                    if legal {
                        let value = try reply(kind, phase, result)
                        let data  = try ServiceSubscriptionFrameCodec.encode(value, profile: .v1_4)
                        #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(data, profile: .v1_4) == value)
                        #expect(try object(data)["result"] as? String == [
                            "accepted", "acquired", "subscribed", "acknowledged", "refused", "outcomeUnknown"
                        ][index])
                        #expect(try JSONDecoder().decode(ServiceControlReply.self, from: encoded(value)) == value)

                        let extra: Set<String> = index == 1
                            ? ["grant"]
                            : index == 2 ? ["subscriptionID"] : index == 4 ? ["failureCode", "failureReason"] : []
                        #expect(Set(try object(data).keys) == extra.union([
                            "schemaVersion", "requestID", "kind", "phase", "result"
                        ]))
                    } else {
                        #expect(throws: (any Error).self) { try reply(kind, phase, result) }

                        // Build a syntactically complete result under a different kind/phase.
                        let legalKind: ServiceControlKind = index == 2 ? .subscribe : index == 3 ? .unsubscribe : .acquire
                        var fields    = try object(encoded(reply(legalKind, index == 0 ? .admission : .terminal, result)))
                        fields["kind"]  = kind.rawValue
                        fields["phase"] = phase.rawValue
                        #expect(throws: (any Error).self) { try decode(json(fields), 1) }
                    }
                }
            }
        }
    }

    @Test
    func repliesCorrelateIdentityKindAndBothScopeFieldsWithoutServiceBindingEquality() throws {
        let acquire = try request()

        for value in [
            try reply(.acquire, .admission, .accepted),
            try reply(.acquire, .terminal, .acquired(grant())),
            try reply(.acquire, .terminal, .refused(code: .resourceDenied, reason: "Denied")),
            try reply(.acquire, .terminal, .outcomeUnknown)
        ] {
            try value.validate(matching: acquire) // binding != contract is intentionally valid.
            #expect(throws: (any Error).self) {
                try value.validate(matching: ServiceControlRequest(requestID: other, action: acquire.action))
            }
            #expect(throws: (any Error).self) {
                try value.validate(matching: request(.subscribe(requirementID: "binding", grantID: other)))
            }
        }

        for token in [try grant(feature: "other"), try grant(operation: "other")] {
            #expect(throws: (any Error).self) {
                try reply(.acquire, .terminal, .acquired(token)).validate(matching: acquire)
            }
        }

        try reply(.subscribe, .terminal, .subscribed(other))
            .validate(matching: request(.subscribe(requirementID: "binding", grantID: other)))
        try reply(.unsubscribe, .terminal, .acknowledged)
            .validate(matching: request(.unsubscribe(subscriptionID: other)))
    }

    @Test
    func sourceShapesRoundtripAndCorrelateEverySpecifiedField() throws {
        let descriptor = try start()
        let data       = try ServiceSubscriptionFrameCodec.encode(descriptor, profile: .v1_4)
        #expect(try ServiceSubscriptionFrameCodec.decodeSourceStart(data, profile: .v1_4) == descriptor)
        #expect(Set(try object(data).keys) == [
            "schemaVersion", "kind", "sourceID", "startNonce", "providerID", "publisher", "digest", "contractVersion",
            "serviceID", "partition", "scope"
        ])

        for output in [ServiceSourceOutput.startupCompleted, .sourceUpdate(try response())] {
            let value = try ServiceSourceOutputFrame(
                sourceID  : id,
                startNonce: other,
                output    : output
            )
            try value.validate(matching: descriptor)

            let data = try ServiceSubscriptionFrameCodec.encode(value, profile: .v1_4)
            #expect(try ServiceSubscriptionFrameCodec.decodeSourceOutput(data, profile: .v1_4) == value)
            #expect(try JSONDecoder().decode(ServiceSourceOutputFrame.self, from: encoded(value)) == value)

            let fields: Set<String> = ["schemaVersion", "kind", "sourceID", "startNonce"]
            #expect(
                try object(data)["kind"] as? String
                    == (output == .startupCompleted ? "startupCompleted" : "sourceUpdate")
            )
            #expect(Set(try object(data).keys) == (output == .startupCompleted ? fields : fields.union(["response"])))

            for (source, nonce) in [(other, other), (id, id)] {
                #expect(throws: (any Error).self) {
                    try ServiceSourceOutputFrame(
                        sourceID  : source,
                        startNonce: nonce,
                        output    : output
                    ).validate(matching: descriptor)
                }
            }
        }

        for payload in [try response(contract: "other"), try response(operation: "other")] {
            #expect(throws: (any Error).self) {
                try ServiceSourceOutputFrame(
                    sourceID  : id,
                    startNonce: other,
                    output    : .sourceUpdate(payload)
                ).validate(matching: descriptor)
            }
        }

        #expect(try JSONDecoder().decode(ServiceSourceStartFrame.self, from: encoded(descriptor)) == descriptor)
    }

    private func fixtures() throws -> [(Int, Data)] {
        [
            (0, try encoded(request())),
            (0, try encoded(request(.subscribe(requirementID: "binding", grantID: other)))),
            (0, try encoded(request(.unsubscribe(subscriptionID: other)))),
            (1, try encoded(reply(.acquire, .admission, .accepted))),
            (1, try encoded(reply(.acquire, .terminal, .acquired(grant())))),
            (1, try encoded(reply(.subscribe, .terminal, .subscribed(other)))),
            (1, try encoded(reply(.unsubscribe, .terminal, .acknowledged))),
            (1, try encoded(reply(.acquire, .terminal, .refused(code: .invalidPayload, reason: "reason")))),
            (1, try encoded(reply(.acquire, .terminal, .outcomeUnknown))), (2, try encoded(start())),
            (3, try encoded(ServiceSourceOutputFrame(sourceID: id, startNonce: other, output: .startupCompleted))),
            (
                3,
                try encoded(ServiceSourceOutputFrame(sourceID: id, startNonce: other, output: .sourceUpdate(response())))
            ),
            (4, try encoded(ServiceEvent(subscriptionID: other, token: grant(), response: response())))
        ]
    }

    @Test
    func everyTopLevelShapeRejectsMissingNullExtraWrongScalarsSchemaDiscriminators() throws {
        for (family, data) in try fixtures() {
            let valid = try object(data)
            try decode(data, family)

            for key in valid.keys {
                for invalid: Any in [NSNull(), ["unexpected": true]] {
                    var changed = valid
                    changed[key] = invalid
                    #expect(throws: (any Error).self) { try decode(json(changed), family) }
                }

                var missing = valid
                missing.removeValue(forKey: key)
                #expect(throws: (any Error).self) { try decode(json(missing), family) }
            }

            for key in [
                "owner", "permissionID", "partition", "lifetime", "provider", "grant", "response", "operation",
                "subscriptionID"
            ] where valid[key] == nil {
                var changed = valid
                changed[key] = NSNull()
                #expect(throws: (any Error).self) { try decode(json(changed), family) }
            }

            for key in ["kind", "phase", "result"] where valid[key] != nil {
                var changed = valid
                changed[key] = "future"
                #expect(throws: (any Error).self) { try decode(json(changed), family) }
            }

            var changed = valid
            changed["schemaVersion"] = 2
            #expect(throws: (any Error).self) { try decode(json(changed), family) }

            for key in ["requestID", "grantID", "subscriptionID", "sourceID", "startNonce"] where valid[key] != nil {
                changed = valid
                changed[key] = "bad-uuid"
                #expect(throws: (any Error).self) { try decode(json(changed), family) }
            }

            try decode(data, family)
        }
    }

    // Recursive security-boundary mutations cover the synthesized generation DTO too.
    private func nestedMutations(_ object: [String: Any]) -> [[String: Any]] {
        var mutations: [[String: Any]] = []

        for (key, child) in object {
            guard let nested = child as? [String: Any] else { continue }

            var bad = nested
            bad["permissionID"] = NSNull()
            var parent = object
            parent[key] = bad
            mutations.append(parent)

            for field in nested.keys {
                bad = nested
                bad[field] = NSNull()
                parent[key] = bad
                mutations.append(parent)

                bad = nested
                bad.removeValue(forKey: field)
                parent[key] = bad
                mutations.append(parent)
            }

            for bad in nestedMutations(nested) {
                parent = object
                parent[key] = bad
                mutations.append(parent)
            }
        }

        return mutations
    }

    @Test
    func closedNestedSecurityFieldsRejectRecursively() throws {
        for (family, data) in try fixtures() {
            for changed in nestedMutations(try object(data)) {
                #expect(throws: (any Error).self) { try decode(json(changed), family) }
            }
        }
    }

    @Test
    func malformedGrantDateResourcesGenerationAndResponseReject() throws {
        let data  = try encoded(reply(.acquire, .terminal, .acquired(grant())))
        let valid = try object(data)
        let token = try #require(valid["grant"] as? [String: Any])

        for (key, bad) in [
            ("expiresAt", "NaN" as Any), ("id", "bad-uuid"), ("owner", "bad"), ("serviceID", "bad space")
        ] {
            var fields  = valid
            var changed = token
            changed[key]    = bad
            fields["grant"] = changed
            #expect(throws: (any Error).self) { try decode(json(fields), 1) }
        }

        for date in [Double.infinity, -Double.infinity, Double.nan] {
            #expect(throws: (any Error).self) {
                try Grant(
                    id        : id,
                    owner     : grant().owner,
                    serviceID : "contract",
                    scope     : scope(),
                    expiresAt : Date(timeIntervalSince1970: date),
                    generation: ConnectionGeneration(),
                    cost      : grant().cost
                )
            }
        }

        let overflow = String(decoding: data, as: UTF8.self).replacingOccurrences(
            of     : #""expiresAt":[^,}]+"#,
            with   : #""expiresAt":1e999"#,
            options: .regularExpression
        )
        #expect(throws: (any Error).self) { try decode(Data(overflow.utf8), 1) }

        for (key, bad) in [
            ("requestedMemoryMiB", -1 as Any), ("requestedMemoryMiB", 65), ("maximumConcurrentWork", 2),
            ("profile", "other"), ("background", "other")
        ] {
            var fields  = valid
            var changed = token
            var cost    = try #require(token["cost"] as? [String: Any])
            cost[key]       = bad
            changed["cost"] = cost
            fields["grant"] = changed
            #expect(throws: (any Error).self) { try decode(json(fields), 1) }
        }

        var fields  = valid
        var changed = token
        changed["generation"] = ["value": "bad-uuid"]
        fields["grant"]       = changed
        #expect(throws: (any Error).self) { try decode(json(fields), 1) }

        for (family, data) in try fixtures() where family >= 3 {
            var fields = try object(data)
            guard var response = fields["response"] as? [String: Any] else { continue }

            response["payload"] = "not base64!"
            fields["response"]  = response
            #expect(throws: (any Error).self) { try decode(json(fields), family) }
        }
    }

    @Test
    func sourceDescriptorUTF8BoundsAndExistingSemVerValidation() throws {
        let valid = try object(encoded(start()))

        for (key, cap) in [("publisher", 256), ("digest", 512), ("partition", 256)] {
            for text in [
                String(repeating: "x", count: cap),
                String(repeating: "é", count: cap / 2),
                String(repeating: "\u{01}", count: cap)
            ] {
                var changed = valid
                changed[key] = text
                let value = try ServiceSubscriptionFrameCodec.decodeSourceStart(json(changed), profile: .v1_4)
                #expect(try object(encoded(value))[key] as? String == text)
            }

            for text in ["", String(repeating: "x", count: cap + 1), String(repeating: "é", count: cap / 2) + "x"] {
                var changed = valid
                changed[key] = text
                #expect(throws: (any Error).self) { try decode(json(changed), 2) }
            }
        }

        for version in ["1.2.3", "1.2.3-0+build.9", "1.2.3+" + String(repeating: "a", count: 122)] {
            var changed = valid
            changed["contractVersion"] = version
            try decode(json(changed), 2)
        }

        for version in ["", "01.2.3", "1.2.3-01", "1.2", "1.2.3+" + String(repeating: "a", count: 123)] {
            var changed = valid
            changed["contractVersion"] = version
            #expect(throws: (any Error).self) { try decode(json(changed), 2) }
        }
    }

    @Test
    func refusalOriginalByteBoundsControlEscapingAndClosedCodes() throws {
        for reason in [String(repeating: "\u{01}", count: 4096), String(repeating: "é", count: 2048), "e\u{301}"] {
            let value = try reply(.acquire, .terminal, .refused(code: .resourceDenied, reason: reason))
            let data  = try ServiceSubscriptionFrameCodec.encode(value, profile: .v1_4)

            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(data, profile: .v1_4) == value)
            #expect(try object(data)["failureReason"] as? String == reason)
            #expect(data.count <= 24_576 + 8192)
        }

        let valid = try object(encoded(reply(.acquire, .terminal, .refused(code: .resourceDenied, reason: "reason"))))
        for reason in ["", String(repeating: "x", count: 4097), String(repeating: "é", count: 2048) + "x"] {
            #expect(throws: (any Error).self) {
                try reply(.acquire, .terminal, .refused(code: .invalidPayload, reason: reason))
            }

            var fields = valid
            fields["failureReason"] = reason
            #expect(throws: (any Error).self) { try decode(json(fields), 1) }
        }

        for code in ["outcomeUnknown", "future"] {
            var fields = valid
            fields["failureCode"] = code
            #expect(throws: (any Error).self) { try decode(json(fields), 1) }
        }

        #expect(throws: (any Error).self) {
            try reply(.acquire, .terminal, .refused(code: .outcomeUnknown, reason: "uncertain"))
        }

        for code in [
            AddonFailure.Code.missingRequirement, .versionConflict, .permissionDenied, .dependencyUnavailable,
            .resolutionTooComplex, .resourceDenied, .rateLimited, .deadlineExceeded, .sessionRevoked, .invalidPayload
        ] {
            let value = try reply(.acquire, .terminal, .refused(code: code, reason: "original"))

            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(
                ServiceSubscriptionFrameCodec.encode(value, profile: .v1_4),
                profile: .v1_4
            ) == value)
        }
    }

    @Test
    func nilProfileEveryEntryAndRawCapPrecedesProfileAndParser() throws {
        let controlRequest = try request()
        let controlReply   = try reply(.acquire, .terminal, .outcomeUnknown)
        let sourceStart    = try start()
        let sourceOutput   = try ServiceSourceOutputFrame(
            sourceID  : id,
            startNonce: other,
            output    : .startupCompleted
        )
        let event = try ServiceEvent(
            subscriptionID: other,
            token         : grant(),
            response      : response()
        )

        semantic(.versionConflict) { _ = try ServiceSubscriptionFrameCodec.encode(controlRequest, profile: nil) }
        semantic(.versionConflict) { _ = try ServiceSubscriptionFrameCodec.encode(controlReply, profile: nil) }
        semantic(.versionConflict) { _ = try ServiceSubscriptionFrameCodec.encode(sourceStart, profile: nil) }
        semantic(.versionConflict) { _ = try ServiceSubscriptionFrameCodec.encode(sourceOutput, profile: nil) }
        semantic(.versionConflict) { _ = try ServiceSubscriptionFrameCodec.encode(event, profile: nil) }

        for family in 0..<5 {
            semantic(.versionConflict) { try decode(Data("poison".utf8), family, nil) }
            for profile in [ServiceSubscriptionFrameProfile.v1_4, nil] {
                semantic(.invalidPayload) { try decode(Data(repeating: 255, count: 196609), family, profile) }
            }
            #expect(throws: DecodingError.self) { try decode(Data(repeating: 255, count: 196608), family) }
        }

        let bytes = try ServiceSubscriptionFrameCodec.encode(controlRequest, profile: .v1_4)
        let exact = Data(repeating: 32, count: 196608 - bytes.count) + bytes
        #expect(try ServiceSubscriptionFrameCodec.decodeControlRequest(exact, profile: .v1_4) == controlRequest)
    }

    @Test
    func decodedPayloadCapAndMaliciousUnicodeWhitespaceExpansion() throws {
        for family in [3, 4] {
            let base   = try fixtures().first { $0.0 == family && (try? object($0.1)["response"]) != nil }!.1
            var fields = try object(base)
            var nested = try #require(fields["response"] as? [String: Any])
            nested["payload"]  = Data(repeating: 255, count: 65537).base64EncodedString()
            fields["response"] = nested

            let tooBig = try json(fields)
            #expect(tooBig.count < 196608)
            semantic(.invalidPayload) { try decode(tooBig, family) }

            let base64 = Data(repeating: 255, count: 65536).base64EncodedString()
            nested["payload"]  = base64
            fields["response"] = nested

            let normal   = try json(fields)
            let expanded = base64.map { String(format: "\\u%04x", $0.asciiValue!) }.joined()
            let poison   = Data(
                String(decoding: normal, as: UTF8.self).replacingOccurrences(of: base64, with: expanded).utf8
            )
            #expect(poison.count > 196608)
            semantic(.invalidPayload) { try decode(poison, family) }
            semantic(.invalidPayload) { try decode(Data(repeating: 32, count: 196609 - normal.count) + normal, family) }
        }
    }

    @Test
    func maximumMetadataAllFFEmittedAndSlashEscapedSourceAndEventFit() throws {
        let bytes = Data(repeating: 255, count: 65536)
        #expect(bytes.base64EncodedString().count == 87384)

        let descriptor = try start(maximum: true)
        let output     = try ServiceSourceOutputFrame(
            sourceID  : id,
            startNonce: other,
            output    : .sourceUpdate(response(bytes, maximum: true))
        )
        let event = try ServiceEvent(
            subscriptionID: other,
            token         : grant(maximum: true),
            response      : response(bytes, maximum: true)
        )
        let sourceOutputData = try ServiceSubscriptionFrameCodec.encode(output, profile: .v1_4)
        let eventData        = try ServiceSubscriptionFrameCodec.encode(event, profile: .v1_4)

        for data in [sourceOutputData, slashEscaped(sourceOutputData)] {
            #expect(try ServiceSubscriptionFrameCodec.decodeSourceOutput(data, profile: .v1_4) == output)
        }
        for data in [eventData, slashEscaped(eventData)] {
            #expect(try ServiceSubscriptionFrameCodec.decodeServiceEvent(data, profile: .v1_4) == event)
        }

        // Conservative fixed punctuation bound, quoted UUID 38, identifier 130,
        // owner 257, largest numeric date 32, memory/concurrency/profile/background.
        func fixed(_ keys: Set<String>) -> Int { 2 + keys.reduce(0) { $0 + $1.utf8.count + 4 } }

        let responseKeys : Set<String> = ["schemaVersion", "contractID", "operation", "payload"]
        let scopeKeys    : Set<String> = ["featureID", "operation"]
        let costKeys     : Set<String> = ["profile", "requestedMemoryMiB", "maximumConcurrentWork", "background"]
        let grantKeys    : Set<String> = ["id", "owner", "serviceID", "scope", "expiresAt", "generation", "cost"]
        let scopeBound    = fixed(scopeKeys) + 260
        let costBound     = fixed(costKeys) + 13 + 32 + 1 + 19
        let grantBound    = fixed(grantKeys) + 38 + 257 + 130 + scopeBound + 32 + fixed(["value"]) + 38 + costBound
        let responseBound = fixed(responseKeys) + 1 + 260 + 2
        let outputBound   = fixed(["schemaVersion", "kind", "sourceID", "startNonce", "response"])
            + 1 + 14 + 76 + responseBound
        let eventBound = fixed(["schemaVersion", "subscriptionID", "token", "response"])
            + 1 + 38 + grantBound + responseBound

        for (data, bound) in [(sourceOutputData, outputBound), (eventData, eventBound)] {
            let escaped = slashEscaped(data)
            #expect(bound < 8192)
            #expect(174768 + bound < 196608)
            #expect(escaped.count <= 174768 + bound)

            var fields = try object(data)
            var nested = try #require(fields["response"] as? [String: Any])
            nested["payload"]  = ""
            fields["response"] = nested
            #expect(try json(fields).count <= bound)
        }

        let token = try #require(try object(eventData)["token"] as? [String: Any])
        #expect(Set(token.keys) == grantKeys)
        #expect((token["owner"] as? String)?.utf8.count == 255)
        #expect(Set(try #require(token["scope"] as? [String: Any]).keys) == scopeKeys)
        #expect(Set(try #require(token["cost"] as? [String: Any]).keys) == costKeys)
        #expect(Set(try #require(token["generation"] as? [String: Any]).keys) == ["value"])
        #expect(String(describing: token["expiresAt"]!).utf8.count <= 32)

        let startData      = try ServiceSubscriptionFrameCodec.encode(descriptor, profile: .v1_4)
        let descriptorKeys: Set<String> = [
            "schemaVersion", "kind", "sourceID", "startNonce", "providerID", "publisher", "digest", "contractVersion",
            "serviceID", "partition", "scope"
        ]
        let descriptorBound = fixed(descriptorKeys) + 1 + 13 + 76 + 257 + 6 + 130 + 130 + scopeBound + 6144
        #expect(Set(try object(startData).keys) == descriptorKeys)
        #expect(descriptorBound < 8192)
        #expect(startData.count <= descriptorBound)

        try output.validate(matching: descriptor)
        #expect(try ServiceSubscriptionFrameCodec.decodeSourceStart(startData, profile: .v1_4) == descriptor)

        let generic = slashEscaped(try encoded(AddonEvent.serviceChanged(event)))
        #expect(generic.count > 131072)
        semantic(.invalidPayload) { _ = try AddonEvent.decode(generic) }
    }

    @Test
    func profilesAndAllFamiliesRemainSeparatedAndSorted() throws {
        for (family, data) in try fixtures() {
            for wrong in 0..<5 where wrong != family {
                #expect(throws: (any Error).self) { try decode(data, wrong) }
            }
            #expect(throws: (any Error).self) { _ = try ServiceFrameCodec.decodeProviderFrame(data, profile: .v1_3) }
            #expect(throws: (any Error).self) { _ = try ServiceFrameCodec.decodeInvocationRequest(data, profile: .v1_3) }
            #expect(throws: (any Error).self) { _ = try ServiceFrameCodec.decodeInvocationReply(data, profile: .v1_3) }
            #expect(throws: (any Error).self) { _ = try AddonEvent.decode(data) }
        }

        let providerInvocation = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : id,
            contractID   : "contract",
            operation    : "read",
            payload      : Data(),
            deadline     : Date()
        )
        let providerFrame = try ServiceFrameCodec.encode(
            ServiceProviderFrame.invocation(providerInvocation),
            profile: .v1_3
        )
        for family in 0..<5 { #expect(throws: (any Error).self) { try decode(providerFrame, family) } }

        for data in [
            try ServiceSubscriptionFrameCodec.encode(request(), profile: .v1_4),
            try ServiceSubscriptionFrameCodec.encode(start(), profile: .v1_4)
        ] {
            // JSONSerialization canonical sorted reencoding differs only in slash policy;
            // these fixtures have no slash, preserving exact sorted output.
            #expect(data == (try json(object(data))))
        }

        semantic(.invalidPayload) { _ = try AddonEvent.decode(Data(repeating: 32, count: 131073)) }
        #expect(ServiceFrameCodec.maximumEncodedBytes == 196608)
    }
}
