//
//  ServiceFrameCodecTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@Suite
struct ServiceFrameCodecTests {

    private let id    = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let grant = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let maxID = String(repeating: "a", count: 128)

    private func invocation(
        _ payload : Data = Data(),
        maximumIDs: Bool = false
    ) throws -> ServiceInvocation {
        try ServiceInvocation(
            schemaVersion: 1,
            requestID    : id,
            contractID   : maximumIDs ? maxID : "contract",
            operation    : maximumIDs ? maxID : "read",
            payload      : payload,
            deadline     : Date(timeIntervalSinceReferenceDate: 1.7976931348623155e308)
        )
    }

    private func request(
        _ payload : Data = Data(),
        maximumIDs: Bool = false
    ) throws -> ServiceInvocationRequest {
        try ServiceInvocationRequest(grantID: grant, invocation: invocation(payload, maximumIDs: maximumIDs))
    }

    private func response(
        _ payload: Data = Data(),
        contract : String = "contract",
        operation: String = "read"
    ) throws -> ServiceResponse {
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : contract,
            operation    : operation,
            payload      : payload
        )
    }

    private func reply(
        _ result : ServiceInvocationResult,
        requestID: UUID? = nil,
        contract : String = "contract",
        operation: String = "read",
        schema   : Int = 1
    ) throws -> ServiceInvocationReply {
        try ServiceInvocationReply(
            schemaVersion: schema,
            requestID    : requestID ?? id,
            contractID   : contract,
            operation    : operation,
            result       : result
        )
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fail(
        _ code  : AddonFailure.Code,
        _ reason: String,
        _ body  : () throws -> Void
    ) {
        do {
            try body()
            Issue.record("Expected \(code): \(reason)")
        } catch let failure as AddonFailure {
            #expect(failure.code == code)
            #expect(failure.reason == reason)
        } catch {
            Issue.record("Expected semantic failure, got \(error)")
        }
    }

    private func decodingError(_ body: () throws -> Void) {
        #expect(throws: DecodingError.self) { try body() }
    }

    private func decode(
        _ data : Data,
        family : Int,
        profile: ServiceInvocationFrameProfile? = .v1_3
    ) throws {
        switch family {
            case 0: _ = try ServiceFrameCodec.decodeInvocationRequest(data, profile: profile)
            case 1: _ = try ServiceFrameCodec.decodeInvocationReply(data, profile: profile)
            default: _ = try ServiceFrameCodec.decodeProviderFrame(data, profile: profile)
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

    // Catches loss of payload/identity or accidental reduced consumer payload bounds.
    @Test
    func requestsRoundtripEmptyAndFullPayload() throws {
        for bytes in [Data(), Data(repeating: 255, count: 65_536)] {
            let value = try request(bytes)
            let data  = try ServiceFrameCodec.encode(value, profile: .v1_3)

            #expect(try ServiceFrameCodec.decodeInvocationRequest(data, profile: .v1_3) == value)
            #expect(try JSONDecoder().decode(ServiceInvocationRequest.self, from: JSONEncoder().encode(value)) == value)
            #expect(Set(try object(data).keys) == ["schemaVersion", "kind", "grantID", "invocation"])
        }

        fail(.invalidPayload, "Unsupported service request schema") {
            _ = try ServiceInvocationRequest(
                schemaVersion: 2,
                grantID      : grant,
                invocation   : invocation()
            )
        }
    }

    // Catches mixed result fields and missing completion correlation integration.
    @Test
    func allReplyResultsRoundtripAndCompletionCorrelates() throws {
        for result in [
            ServiceInvocationResult.completed(try response(Data(repeating: 255, count: 65_536))),
            .refused(code: .permissionDenied, reason: "Denied"), .outcomeUnknown
        ] {
            let value = try reply(result)
            try value.validate(matching: request())

            let data = try ServiceFrameCodec.encode(value, profile: .v1_3)
            #expect(try ServiceFrameCodec.decodeInvocationReply(data, profile: .v1_3) == value)
            #expect(try JSONDecoder().decode(ServiceInvocationReply.self, from: JSONEncoder().encode(value)) == value)

            let base : Set<String> = ["schemaVersion", "requestID", "contractID", "operation", "result"]
            let extra: Set<String>
            switch result {
                case .completed(let response):
                    extra = ["response"]
                    try InvocationCompletion.service(requestID: id, response: response).validateCorrelation(
                        .service(requestID: id, contractID: "contract", operation: "read")
                    )

                case .refused: extra = ["failureCode", "failureReason"]
                case .outcomeUnknown: extra = []
            }

            #expect(Set(try object(data).keys) == base.union(extra))
        }
    }

    // Catches routing full payload through the generic event's smaller raw bound.
    @Test
    func providerFullPayloadRoundtrip() throws {
        let value = ServiceProviderFrame.invocation(try invocation(Data(repeating: 255, count: 65_536)))
        try value.validate()
        let data = try ServiceFrameCodec.encode(value, profile: .v1_3)

        #expect(try ServiceFrameCodec.decodeProviderFrame(data, profile: .v1_3) == value)
        #expect(try JSONDecoder().decode(ServiceProviderFrame.self, from: JSONEncoder().encode(value)) == value)
    }

    // Enumerates the invocation frame keys and scalars; no owner or subscription fields, and no allocator-space claim.
    @Test
    func maximumInvocationFrameMetadataAndSlashEscapedPayloadFit() throws {
        let payload = Data(repeating: 255, count: 65_536)
        #expect(payload.base64EncodedString().count == 87_384)

        let consumer  = try request(payload, maximumIDs: true)
        let provider  = ServiceProviderFrame.invocation(consumer.invocation)
        let completed = try reply(
            .completed(response(payload, contract: maxID, operation: maxID)),
            contract : maxID,
            operation: maxID
        )
        let data = [
            try ServiceFrameCodec.encode(consumer, profile: .v1_3),
            try ServiceFrameCodec.encode(completed, profile: .v1_3),
            try ServiceFrameCodec.encode(provider, profile: .v1_3)
        ]
        let invocationKeys: Set<String> = [
            "schemaVersion", "requestID", "contractID", "operation", "payload", "deadline"
        ]
        let responseKeys: Set<String> = ["schemaVersion", "contractID", "operation", "payload"]

        // Worst fixed punctuation: 2 braces/object + comma/key + quoted key/colon.
        // UUID=38 quoted bytes, identifier=130 quoted bytes, schema=1, finite Double<=32.
        func fixed(_ keys: Set<String>) -> Int { 2 + keys.reduce(0) { $0 + $1.utf8.count + 4 } }

        let invocationMetadata = fixed(invocationKeys) + 1 + 38 + 130 + 130 + 32 + 2
        let responseMetadata   = fixed(responseKeys) + 1 + 130 + 130 + 2
        let bounds             = [
            fixed(["schemaVersion", "kind", "grantID", "invocation"]) + 1 + 8 + 38 + invocationMetadata,
            fixed(["schemaVersion", "requestID", "contractID", "operation", "result", "response"])
                + 1 + 38 + 130 + 130 + 11 + responseMetadata,
            fixed(["schemaVersion", "kind", "invocation"]) + 1 + 16 + invocationMetadata
        ]

        for family in 0..<3 {
            let escaped = slashEscaped(data[family])
            #expect(bounds[family] <= 8_192)
            #expect(174_768 + bounds[family] < 196_608)
            #expect(escaped.count <= 174_768 + bounds[family])
            try decode(escaped, family: family)
            #expect(try object(data[family])["owner"] == nil)
        }

        #expect(try ServiceFrameCodec.decodeInvocationRequest(slashEscaped(data[0]), profile: .v1_3) == consumer)
        #expect(try ServiceFrameCodec.decodeProviderFrame(slashEscaped(data[2]), profile: .v1_3) == provider)

        let nested = try #require(try object(data[0])["invocation"] as? [String: Any])
        #expect(Set(nested.keys) == invocationKeys)
        #expect(String(describing: nested["deadline"]!).utf8.count <= 32)
        #expect(Set(try #require(try object(data[1])["response"] as? [String: Any]).keys) == responseKeys)

        // Enumerate the two payload-free invocation result wrappers too. The longest
        // existing code is dependencyUnavailable (21 ASCII bytes, 23 quoted).
        let refusalKeys: Set<String> = [
            "schemaVersion", "requestID", "contractID", "operation", "result", "failureCode", "failureReason"
        ]
        let unknownKeys    : Set<String> = ["schemaVersion", "requestID", "contractID", "operation", "result"]
        let refusalMetadata = fixed(refusalKeys) + 1 + 38 + 130 + 130 + 9 + 23 + 2
        let unknownMetadata = fixed(unknownKeys) + 1 + 38 + 130 + 130 + 16
        #expect(refusalMetadata <= 8_192)
        #expect(unknownMetadata <= 8_192)

        let refusal = try reply(
            .refused(code: .dependencyUnavailable, reason: String(repeating: "\u{01}", count: 4_096)),
            contract : maxID,
            operation: maxID
        )
        let refusalData = try ServiceFrameCodec.encode(refusal, profile: .v1_3)
        #expect(Set(try object(refusalData).keys) == refusalKeys)
        #expect(refusalData.count <= 24_576 + refusalMetadata)
        #expect(24_576 + refusalMetadata < 196_608)

        let unknown = try reply(
            .outcomeUnknown,
            contract : maxID,
            operation: maxID
        )
        let unknownData = try ServiceFrameCodec.encode(unknown, profile: .v1_3)
        #expect(Set(try object(unknownData).keys) == unknownKeys)
        #expect(unknownData.count <= unknownMetadata)
    }

    // Raw rejection must precede BOTH profile gating and Foundation parsing.
    @Test
    func rawOversizeWhitespaceUnicodeRejectBeforeProfileAndDecode() throws {
        let base = try json(object(ServiceFrameCodec.encode(
            request(Data(repeating: 255, count: 65_536)),
            profile: .v1_3
        )))
        let base64   = Data(repeating: 255, count: 65_536).base64EncodedString()
        let unicode  = base64.map { String(format: "\\u%04x", $0.asciiValue!) }.joined()
        let expanded = Data(String(decoding: base, as: UTF8.self).replacingOccurrences(of: base64, with: unicode).utf8)
        let inputs   = [Data(repeating: 255, count: 196_609), Data(repeating: 32, count: 196_609) + base, expanded]

        for data in inputs {
            #expect(data.count > 196_608)
            for family in 0..<3 {
                for profile in [ServiceInvocationFrameProfile.v1_3, nil] {
                    fail(.invalidPayload, "Service frame exceeds 192 KiB") {
                        try decode(data, family: family, profile: profile)
                    }
                }
            }
        }

        for family in 0..<3 {
            decodingError { try decode(Data(repeating: 255, count: 196_608), family: family) }
        }

        let small = try ServiceFrameCodec.encode(request(), profile: .v1_3)
        let exact = Data(repeating: 32, count: 196_608 - small.count) + small
        #expect(try ServiceFrameCodec.decodeInvocationRequest(exact, profile: .v1_3) == request())
    }

    // Decoded cap is independent of raw cap, applies to invocation AND completed response.
    @Test
    func decodedPayloadCapRejectsUnderRawCap() throws {
        let payload = Data(repeating: 0, count: 65_537).base64EncodedString()

        for family in 0..<3 {
            var fields: [String: Any]
            if family == 1 {
                fields = try object(ServiceFrameCodec.encode(reply(.completed(response())), profile: .v1_3))
                var nested = try #require(fields["response"] as? [String: Any])
                nested["payload"]  = payload
                fields["response"] = nested
            } else {
                fields = try object(ServiceFrameCodec.encode(request(), profile: .v1_3))
                if family == 2 {
                    fields.removeValue(forKey: "grantID")
                    fields["kind"] = "providerInvoke"
                }
                var nested = try #require(fields["invocation"] as? [String: Any])
                nested["payload"]    = payload
                fields["invocation"] = nested
            }

            let data = try json(fields)
            #expect(data.count < 196_608)
            fail(.invalidPayload, "Service payload exceeds 64 KiB") { try decode(data, family: family) }
        }
    }

    // Each closed field set rejects additions, missing keys and null placeholders.
    @Test
    func closedShapesSchemaKindsAndResultsReject() throws {
        let fixtures: [(Int, [String: Any], String)] = [
            (0, try object(ServiceFrameCodec.encode(request(), profile: .v1_3)), "Invalid service request fields"),
            (
                2,
                try object(ServiceFrameCodec.encode(ServiceProviderFrame.invocation(invocation()), profile: .v1_3)),
                "Invalid service provider fields"
            )
        ] + (try [
            ServiceInvocationResult.completed(response()),
            .refused(code: .invalidPayload, reason: "reason"),
            .outcomeUnknown
        ].map {
            (1, try object(ServiceFrameCodec.encode(reply($0), profile: .v1_3)), "Invalid service reply fields")
        })

        for (family, valid, reason) in fixtures {
            try decode(json(valid), family: family)

            for key in valid.keys {
                var fields = valid
                fields.removeValue(forKey: key)
                if key == "result" || key == "kind" {
                    decodingError { try decode(json(fields), family: family) }
                } else {
                    fail(.invalidPayload, reason) { try decode(json(fields), family: family) }
                }

                fields = valid
                fields[key] = NSNull()
                decodingError { try decode(json(fields), family: family) }
            }

            for key in [
                "owner", "partition", "provider", "session", "generation", "permissionID", "requestID", "grantID",
                "response", "failureCode", "failureReason", "invocation"
            ] where valid[key] == nil {
                var fields = valid
                fields[key] = NSNull()
                fail(.invalidPayload, reason) { try decode(json(fields), family: family) }
            }

            var fields = valid
            fields["schemaVersion"] = 2
            let schemaReason = family == 0
                ? "Unsupported service request schema"
                : family == 1 ? "Invalid service reply" : "Unsupported service provider schema"
            fail(.invalidPayload, schemaReason) { try decode(json(fields), family: family) }

            fields = valid
            fields[family == 1 ? "result" : "kind"] = "future"
            fail(
                .invalidPayload,
                family == 1
                    ? "Unknown service result"
                    : family == 0 ? "Unknown service request kind" : "Unknown service provider kind"
            ) {
                try decode(json(fields), family: family)
            }
        }

        for family in 0..<3 {
            let valid  = fixtures.first { $0.0 == family }!.1
            let key    = family == 1 ? "response" : "invocation"
            let nested = try #require(valid[key] as? [String: Any])

            for field in nested.keys {
                var fields  = valid
                var changed = nested
                changed.removeValue(forKey: field)
                fields[key] = changed
                decodingError { try decode(json(fields), family: family) }

                changed = nested
                changed[field] = NSNull()
                fields[key]    = changed
                decodingError { try decode(json(fields), family: family) }
            }

            var fields  = valid
            var changed = nested
            changed["owner"] = "foreign"
            fields[key]      = changed
            fail(.invalidPayload, "Unknown wire field") { try decode(json(fields), family: family) }
        }
    }

    // Failed decodes cannot alter subsequent valid values; exercise UUID/type/deadline boundaries.
    @Test
    func wrongUUIDTypesAndNonfiniteDatesRejectWithoutState() throws {
        for family in 0..<3 {
            let good: Data
            switch family {
                case 0: good = try ServiceFrameCodec.encode(request(), profile: .v1_3)
                case 1: good = try ServiceFrameCodec.encode(reply(.outcomeUnknown), profile: .v1_3)
                default:
                    good = try ServiceFrameCodec.encode(ServiceProviderFrame.invocation(invocation()), profile: .v1_3)
            }

            let valid = try object(good)
            for key in valid.keys {
                var fields = valid
                fields[key] = ["wrong": true]
                if key == "invocation" {
                    fail(.invalidPayload, "Unknown wire field") { try decode(json(fields), family: family) }
                } else {
                    decodingError { try decode(json(fields), family: family) }
                }
                try decode(good, family: family)
            }

            if family != 2 {
                var fields = valid
                fields[family == 0 ? "grantID" : "requestID"] = "not-a-uuid"
                decodingError { try decode(json(fields), family: family) }
            }

            if family != 1 {
                let nested = try #require(valid["invocation"] as? [String: Any])
                for field in nested.keys {
                    var fields  = valid
                    var changed = nested
                    changed[field]       = field == "schemaVersion" || field == "deadline" ? "wrong" as Any : 12 as Any
                    fields["invocation"] = changed
                    decodingError { try decode(json(fields), family: family) }
                }

                for (key, wrong) in [
                    ("requestID", "bad" as Any), ("deadline", "NaN" as Any),
                    ("deadline", NSNull()), ("payload", 12 as Any)
                ] {
                    var fields = valid
                    var nested = try #require(fields["invocation"] as? [String: Any])
                    nested[key]          = wrong
                    fields["invocation"] = nested
                    decodingError { try decode(json(fields), family: family) }
                }

                let text = String(decoding: good, as: UTF8.self)
                // Foundation NSNumber formatting may differ: replace numeric deadline via regex.
                let overflow = text.replacingOccurrences(
                    of     : "\"deadline\":[^,}]+",
                    with   : "\"deadline\":1e999",
                    options: .regularExpression
                )
                decodingError { try decode(Data(overflow.utf8), family: family) }
            }

            try decode(good, family: family)
        }

        for value in [Double.infinity, -Double.infinity, Double.nan] {
            fail(.invalidPayload, "Date must be finite") {
                _ = try ServiceInvocation(
                    schemaVersion: 1,
                    requestID    : id,
                    contractID   : "contract",
                    operation    : "read",
                    payload      : Data(),
                    deadline     : Date(timeIntervalSince1970: value)
                )
            }
        }
    }

    // Every result must match ALL outer identity fields; completed also matches nested response.
    @Test
    func everyResultRejectsIdentityAndNestedResponseMismatch() throws {
        for result in [
            ServiceInvocationResult.completed(try response()),
            .refused(code: .deadlineExceeded, reason: "Late"),
            .outcomeUnknown
        ] {
            for value in [
                try reply(result, requestID: grant),
                try reply(result, contract: "other"),
                try reply(result, operation: "other")
            ] {
                fail(.invalidPayload, "Service reply request mismatch") { try value.validate(matching: request()) }
            }
        }

        for mismatched in [try response(contract: "other"), try response(operation: "other")] {
            fail(.invalidPayload, "Service response request mismatch") {
                try reply(.completed(mismatched)).validate(matching: request())
            }
        }

        for (contract, operation, schema) in [
            ("", "read", 1), ("contract", "", 1), ("contract", "read", 2), (maxID + "a", "read", 1)
        ] {
            fail(.invalidPayload, "Invalid service reply") {
                _ = try reply(
                    .outcomeUnknown,
                    contract : contract,
                    operation: operation,
                    schema   : schema
                )
            }
        }
    }

    // Refusal validates original UTF8 without AddonFailure's convenience truncation.
    @Test
    func failureReasonBytesCodesAndContradictoryUnknownReject() throws {
        for reason in [String(repeating: "\u{01}", count: 4_096), String(repeating: "é", count: 2_048)] {
            let value = try reply(.refused(code: .resourceDenied, reason: reason))
            let data  = try ServiceFrameCodec.encode(value, profile: .v1_3)

            #expect(data.count <= 24_576 + 8_192)
            #expect(try ServiceFrameCodec.decodeInvocationReply(data, profile: .v1_3) == value)
        }

        let base = try object(ServiceFrameCodec.encode(
            reply(.refused(code: .invalidPayload, reason: "reason")),
            profile: .v1_3
        ))
        for reason in ["", String(repeating: "x", count: 4_097), String(repeating: "é", count: 2_048) + "x"] {
            fail(.invalidPayload, "Invalid service failure reason") {
                _ = try reply(.refused(code: .invalidPayload, reason: reason))
            }

            var fields = base
            fields["failureReason"] = reason
            fail(.invalidPayload, "Invalid service failure reason") { try decode(json(fields), family: 1) }
        }

        var fields = base
        fields["failureCode"] = "future"
        fail(.invalidPayload, "Unknown service failure code") { try decode(json(fields), family: 1) }

        fields["failureCode"] = 12
        decodingError { try decode(json(fields), family: 1) }

        fields["failureCode"] = "outcomeUnknown"
        fail(.invalidPayload, "Refused result cannot carry outcomeUnknown") { try decode(json(fields), family: 1) }
        fail(.invalidPayload, "Refused result cannot carry outcomeUnknown") {
            _ = try reply(.refused(code: .outcomeUnknown, reason: "uncertain"))
        }

        for code in [
            AddonFailure.Code.missingRequirement, .versionConflict, .permissionDenied, .dependencyUnavailable,
            .resolutionTooComplex, .resourceDenied, .rateLimited, .deadlineExceeded, .sessionRevoked, .invalidPayload
        ] {
            let value = try reply(.refused(code: code, reason: "original"))

            #expect(try ServiceFrameCodec.decodeInvocationReply(
                ServiceFrameCodec.encode(value, profile: .v1_3),
                profile: .v1_3
            ) == value)
        }
    }

    // Syntax profile authenticates nothing and does not silently enable transport authority.
    @Test
    func nilProfileRejectsEveryCodecEntryPoint() throws {
        let consumerRequest = try request()
        let reply           = try reply(.outcomeUnknown)
        let providerFrame   = ServiceProviderFrame.invocation(consumerRequest.invocation)

        fail(.versionConflict, "Service frames require syntax profile 1.3") {
            _ = try ServiceFrameCodec.encode(consumerRequest, profile: nil)
        }
        fail(.versionConflict, "Service frames require syntax profile 1.3") {
            _ = try ServiceFrameCodec.encode(reply, profile: nil)
        }
        fail(.versionConflict, "Service frames require syntax profile 1.3") {
            _ = try ServiceFrameCodec.encode(providerFrame, profile: nil)
        }
        for family in 0..<3 {
            fail(.versionConflict, "Service frames require syntax profile 1.3") {
                try decode(Data("poison".utf8), family: family, profile: nil)
            }
        }

        #expect(
            Set(try object(ServiceFrameCodec.encode(consumerRequest, profile: .v1_3)).keys)
                == ["schemaVersion", "kind", "grantID", "invocation"]
        )
    }

    // Dedicated bound cannot be achieved by increasing unchanged AddonEvent bound.
    @Test
    func dedicatedProviderSucceedsGenericEventStillDenies() throws {
        let providerInvocation = try invocation(Data(repeating: 255, count: 65_536), maximumIDs: true)
        let dedicated          = slashEscaped(
            try ServiceFrameCodec.encode(ServiceProviderFrame.invocation(providerInvocation), profile: .v1_3)
        )
        #expect(try ServiceFrameCodec.decodeProviderFrame(dedicated, profile: .v1_3) == .invocation(providerInvocation))

        let generic = slashEscaped(try JSONEncoder().encode(AddonEvent.serviceRequest(providerInvocation)))
        #expect(generic.count > 131_072)
        fail(.invalidPayload, "Event exceeds 128 KiB") { _ = try AddonEvent.decode(generic) }
        decodingError { _ = try AddonEvent.decode(Data(repeating: 255, count: 131_072)) }
        fail(.invalidPayload, "Event exceeds 128 KiB") {
            _ = try AddonEvent.decode(Data(repeating: 255, count: 131_073))
        }
    }
}
