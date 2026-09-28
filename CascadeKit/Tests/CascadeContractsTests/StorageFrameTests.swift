//
//  StorageFrameTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@Suite struct StorageFrameTests {
    private let requestID = UUID()

    private func invalid(_ body: () throws -> Void) {
        #expect(throws: (any Error).self) { try body() }
    }

    private func failure(
        _ code: AddonFailure.Code,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            Issue.record("Expected \(code)")
        } catch let error as AddonFailure {
            #expect(error.code == code)
        } catch {
            Issue.record("Expected semantic \(code), received \(error)")
        }
    }

    private func json(_ fields: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: fields,
            options       : [.sortedKeys]
        )
    }

    private func requestFields() -> [String: Any] {
        ["schemaVersion": 1, "requestID": requestID.uuidString, "operation": "read", "key": "key"]
    }

    private func responseFields() -> [String: Any] {
        ["schemaVersion": 1, "requestID": requestID.uuidString, "operation": "read", "result": "missing"]
    }

    @Test func successfulResultsAndFailuresRoundTripAndCorrelate() throws {
        for operation in [StorageOperation.read, .write, .remove] {
            let request = try StorageRequest(
                requestID: requestID,
                operation: operation,
                key      : "../a/b",
                value    : operation == .write ? Data() : nil
            )
            let requestData = try StorageFrameCodec.encode(
                request,
                profile: .v1_1
            )
            #expect(
                try StorageFrameCodec.decodeRequest(
                    requestData,
                    profile: .v1_1
                ) == request
            )
            let success = try StorageResponse(
                requestID: requestID,
                operation: operation,
                result   : operation == .read ? .missing : .acknowledged
            )
            let failure = try StorageResponse(
                requestID    : requestID,
                operation    : operation,
                result       : .failure,
                failureCode  : .outcomeUnknown,
                failureReason: "Unknown outcome"
            )
            for response in [success, failure] {
                try response.validate(matching: request)
                #expect(
                    try StorageFrameCodec.decodeResponse(
                        StorageFrameCodec.encode(
                            response,
                            profile: .v1_1
                        ),
                        profile: .v1_1
                    ) == response
                )
            }
        }
        let presentEmpty = try StorageResponse(
            requestID: requestID,
            operation: .read,
            result   : .value,
            value    : Data()
        )
        let missing = try StorageResponse(
            requestID: requestID,
            operation: .read,
            result   : .missing
        )
        #expect(presentEmpty != missing)
        #expect(
            try StorageFrameCodec.decodeResponse(
                StorageFrameCodec.encode(
                    presentEmpty,
                    profile: .v1_1
                ),
                profile: .v1_1
            ) == presentEmpty
        )
        failure(.invalidPayload) {
            try missing.validate(
                matching: StorageRequest(
                    requestID: UUID(),
                    operation: .read,
                    key      : "key"
                )
            )
        }
        failure(.invalidPayload) {
            try missing.validate(
                matching: StorageRequest(
                    requestID: requestID,
                    operation: .remove,
                    key      : "key"
                )
            )
        }
    }

    @Test func maximumSlashHeavyValueAndEscapedKeyFitDedicatedFrame() throws {
        let value = Data(
            repeating: 255,
            count    : 65_536
        )
        let key = String(
            repeating: "\u{01}",
            count    : 256
        )
        let request = try StorageRequest(
            requestID: requestID,
            operation: .write,
            key      : key,
            value    : value
        )
        let encoded = try StorageFrameCodec.encode(
            request,
            profile: .v1_1
        )
        #expect(encoded.count <= StorageFrameCodec.maximumEncodedBytes)
        #expect(
            try StorageFrameCodec.decodeRequest(
                encoded,
                profile: .v1_1
            ) == request
        )
        let response = try StorageResponse(
            requestID: requestID,
            operation: .read,
            result   : .value,
            value    : value
        )
        let responseData = try StorageFrameCodec.encode(
            response,
            profile: .v1_1
        )
        #expect(responseData.count <= StorageFrameCodec.maximumEncodedBytes)
        #expect(
            try StorageFrameCodec.decodeResponse(
                responseData,
                profile: .v1_1
            ) == response
        )
        #expect(174_768 + 1_536 + 512 < StorageFrameCodec.maximumEncodedBytes)
        #expect(StorageFrameCodec.maximumEncodedBytes < 512 * 1_024)
        failure(.invalidPayload) {
            _ = try ServiceInvocation(
                schemaVersion: 1,
                requestID    : requestID,
                contractID   : "storage",
                operation    : "write",
                payload      : encoded,
                deadline     : Date()
            )
        }
        failure(.invalidPayload) {
            _ = try ServiceResponse(
                schemaVersion: 1,
                contractID   : "storage",
                operation    : "read",
                payload      : responseData
            )
        }
    }

    @Test func keysRemainByteAddressedAndRespectUTF8Limits() throws {
        let composed = try StorageRequest(
            requestID: requestID,
            operation: .read,
            key      : "é"
        )
        let decomposed = try StorageRequest(
            requestID: requestID,
            operation: .read,
            key      : "e\u{301}"
        )
        #expect(composed.key == decomposed.key)
        #expect(composed != decomposed)
        for key in [
            String(
                repeating: "é",
                count    : 128
            ),
            String(
                repeating: "e\u{301}",
                count    : 85
            ) + "x", " /../. ", "\"\\/\n\t",
        ] {
            let request = try StorageRequest(
                requestID: requestID,
                operation: .read,
                key      : key
            )
            let decoded = try StorageFrameCodec.decodeRequest(
                StorageFrameCodec.encode(
                    request,
                    profile: .v1_1
                ),
                profile: .v1_1
            )
            #expect(decoded.key.utf8.elementsEqual(key.utf8))
        }
        for key in [
            "",
            String(
                repeating: "x",
                count    : 257
            ), "a\0b",
            String(
                repeating: "é",
                count    : 129
            ),
        ] {
            failure(.invalidPayload) {
                _ = try StorageRequest(
                    requestID: requestID,
                    operation: .read,
                    key      : key
                )
            }
        }
    }

    @Test func constructorsRejectEveryInvalidOutcomeShape() {
        for schema in [0, 2] {
            failure(.invalidPayload) {
                _ = try StorageRequest(
                    schemaVersion: schema,
                    requestID    : requestID,
                    operation    : .read,
                    key          : "k"
                )
            }
            failure(.invalidPayload) {
                _ = try StorageResponse(
                    schemaVersion: schema,
                    requestID    : requestID,
                    operation    : .read,
                    result       : .missing
                )
            }
        }
        for operation in [StorageOperation.read, .remove] {
            failure(.invalidPayload) {
                _ = try StorageRequest(
                    requestID: requestID,
                    operation: operation,
                    key      : "k",
                    value    : Data()
                )
            }
        }
        failure(.invalidPayload) {
            _ = try StorageRequest(
                requestID: requestID,
                operation: .write,
                key      : "k"
            )
        }
        failure(.invalidPayload) {
            _ = try StorageRequest(
                requestID: requestID,
                operation: .write,
                key      : "k",
                value    : Data(
                    repeating: 0,
                    count    : 65_537
                )
            )
        }
        for operation in [StorageOperation.read, .write, .remove] {
            for result in [StorageResultKind.value, .missing, .acknowledged, .failure] {
                if result == .value || result == .failure || (operation == .read && result == .acknowledged)
                    || (operation != .read && result == .missing)
                {
                    failure(.invalidPayload) {
                        _ = try StorageResponse(
                            requestID: requestID,
                            operation: operation,
                            result   : result
                        )
                    }
                }
            }
            failure(.invalidPayload) {
                _ = try StorageResponse(
                    requestID    : requestID,
                    operation    : operation,
                    result       : .failure,
                    value        : Data(),
                    failureCode  : .invalidPayload,
                    failureReason: "reason"
                )
            }
        }
        for operation in [StorageOperation.write, .remove] {
            failure(.invalidPayload) {
                _ = try StorageResponse(
                    requestID: requestID,
                    operation: operation,
                    result   : .value,
                    value    : Data()
                )
            }
        }
        failure(.invalidPayload) {
            _ = try StorageResponse(
                requestID: requestID,
                operation: .read,
                result   : .value,
                value    : Data(
                    repeating: 0,
                    count    : 65_537
                )
            )
        }
        for result in [StorageResultKind.value, .missing, .acknowledged] {
            failure(.invalidPayload) {
                _ = try StorageResponse(
                    requestID  : requestID,
                    operation  : result == .acknowledged ? .write : .read,
                    result     : result,
                    value      : result == .value ? Data() : nil,
                    failureCode: .invalidPayload
                )
            }
            failure(.invalidPayload) {
                _ = try StorageResponse(
                    requestID    : requestID,
                    operation    : result == .acknowledged ? .write : .read,
                    result       : result,
                    value        : result == .value ? Data() : nil,
                    failureReason: "reason"
                )
            }
        }
    }

    @Test func requestsRejectClosedFieldsNullsAndUnknownDiscriminantsBeforeValue() throws {
        for key in requestFields().keys {
            var fields = requestFields()
            fields.removeValue(forKey: key)
            invalid {
                _ = try StorageFrameCodec.decodeRequest(
                    json(fields),
                    profile: .v1_1
                )
            }
            fields = requestFields()
            fields[key] = NSNull()
            invalid {
                _ = try StorageFrameCodec.decodeRequest(
                    json(fields),
                    profile: .v1_1
                )
            }
        }
        for (key, value) in [
            ("value", NSNull() as Any), ("value", ["poison": true] as Any), ("owner", "foreign" as Any),
            ("schemaVersion", 2 as Any), ("operation", "future" as Any),
        ] {
            var fields = requestFields()
            fields[key] = value
            failure(.invalidPayload) {
                _ = try StorageFrameCodec.decodeRequest(
                    json(fields),
                    profile: .v1_1
                )
            }
        }
        var fields = requestFields()
        fields["operation"] = "write"
        failure(.invalidPayload) {
            _ = try StorageFrameCodec.decodeRequest(
                json(fields),
                profile: .v1_1
            )
        }
        fields["value"] = NSNull()
        invalid {
            _ = try StorageFrameCodec.decodeRequest(
                json(fields),
                profile: .v1_1
            )
        }
        fields["value"] = Data(
            repeating: 0,
            count    : 65_537
        ).base64EncodedString()
        failure(.invalidPayload) {
            _ = try StorageFrameCodec.decodeRequest(
                json(fields),
                profile: .v1_1
            )
        }
    }

    @Test func responsesRejectClosedFieldsAndNulls() throws {
        let outcomes: [(String, [String: Any])] = [
            ("missing", [:]), ("value", ["value": ""]),
            ("failure", ["failureCode": "outcomeUnknown", "failureReason": "reason"]),
            ("acknowledged", ["operation": "write"]),
        ]
        for (result, additions) in outcomes {
            var valid = responseFields()
            valid["result"] = result
            valid.merge(additions) { _, new in new }
            _ = try StorageFrameCodec.decodeResponse(
                json(valid),
                profile: .v1_1
            )
            for key in valid.keys {
                var fields = valid
                fields.removeValue(forKey: key)
                invalid {
                    _ = try StorageFrameCodec.decodeResponse(
                        json(fields),
                        profile: .v1_1
                    )
                }
                fields = valid
                fields[key] = NSNull()
                invalid {
                    _ = try StorageFrameCodec.decodeResponse(
                        json(fields),
                        profile: .v1_1
                    )
                }
            }
            for key in ["key", "owner", "value", "failureCode", "failureReason"] where valid[key] == nil {
                var fields = valid
                fields[key] = NSNull()
                failure(.invalidPayload) {
                    _ = try StorageFrameCodec.decodeResponse(
                        json(fields),
                        profile: .v1_1
                    )
                }
            }
        }
        for (key, value) in [
            ("schemaVersion", 0 as Any), ("operation", "future" as Any), ("result", "future" as Any),
        ] {
            var fields = responseFields()
            fields[key] = value
            failure(.invalidPayload) {
                _ = try StorageFrameCodec.decodeResponse(
                    json(fields),
                    profile: .v1_1
                )
            }
        }
    }

    @Test func failureReasonsAreValidatedWithoutTruncation() throws {
        let reason = String(
            repeating: "\u{01}",
            count    : 4_096
        )
        let response = try StorageResponse(
            requestID    : requestID,
            operation    : .read,
            result       : .failure,
            failureCode  : .outcomeUnknown,
            failureReason: reason
        )
        let encoded = try StorageFrameCodec.encode(
            response,
            profile: .v1_1
        )
        #expect(encoded.count <= StorageFrameCodec.maximumEncodedBytes)
        #expect(
            try StorageFrameCodec.decodeResponse(
                encoded,
                profile: .v1_1
            ) == response
        )
        for reason in [
            "",
            String(
                repeating: "x",
                count    : 4_097
            ),
        ] {
            failure(.invalidPayload) {
                _ = try StorageResponse(
                    requestID    : requestID,
                    operation    : .read,
                    result       : .failure,
                    failureCode  : .invalidPayload,
                    failureReason: reason
                )
            }
            var fields = responseFields()
            fields.merge(["result": "failure", "failureCode": "invalidPayload", "failureReason": reason]) {
                _,
                new in new
            }
            failure(.invalidPayload) {
                _ = try StorageFrameCodec.decodeResponse(
                    json(fields),
                    profile: .v1_1
                )
            }
        }
        var fields = responseFields()
        fields.merge(["result": "failure", "failureCode": "future", "failureReason": "reason"]) { _, new in
            new
        }
        failure(.invalidPayload) {
            _ = try StorageFrameCodec.decodeResponse(
                json(fields),
                profile: .v1_1
            )
        }
        fields["failureCode"] = 3
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeResponse(
                json(fields),
                profile: .v1_1
            )
        }
    }

    @Test func profileAndRawBoundPrecedeJSONParsing() throws {
        let poison    = Data("not json".utf8)
        let oversized = Data(
            repeating: 255,
            count    : StorageFrameCodec.maximumEncodedBytes + 1
        )
        for data in [poison, oversized] {
            failure(.versionConflict) {
                _ = try StorageFrameCodec.decodeRequest(
                    data,
                    profile: nil
                )
            }
            failure(.versionConflict) {
                _ = try StorageFrameCodec.decodeResponse(
                    data,
                    profile: nil
                )
            }
        }
        failure(.invalidPayload) {
            _ = try StorageFrameCodec.decodeRequest(
                oversized,
                profile: .v1_1
            )
        }
        failure(.invalidPayload) {
            _ = try StorageFrameCodec.decodeResponse(
                oversized,
                profile: .v1_1
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeRequest(
                poison,
                profile: .v1_1
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeResponse(
                poison,
                profile: .v1_1
            )
        }
        failure(.versionConflict) {
            _ = try StorageFrameCodec.encode(
                StorageRequest(
                    requestID: requestID,
                    operation: .read,
                    key      : "k"
                ),
                profile: nil
            )
        }
        failure(.versionConflict) {
            _ = try StorageFrameCodec.encode(
                StorageResponse(
                    requestID: requestID,
                    operation: .read,
                    result   : .missing
                ),
                profile: nil
            )
        }
        var fields = requestFields()
        fields["operation"] = 1
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeRequest(
                json(fields),
                profile: .v1_1
            )
        }
        var response = responseFields()
        response["result"] = 1
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeResponse(
                json(response),
                profile: .v1_1
            )
        }
    }
    @Test func exactWireFieldsDirectCodableAndZeroCorrelationRemainValid() throws {
        let zeroID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        for operation in [StorageOperation.read, .write, .remove] {
            let request = try StorageRequest(
                requestID: zeroID,
                operation: operation,
                key      : "key",
                value    : operation == .write ? Data() : nil
            )
            let encoded = try StorageFrameCodec.encode(
                request,
                profile: .v1_1
            )
            let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            let expected: Set<String> =
                operation == .write
                ? ["schemaVersion", "requestID", "operation", "key", "value"]
                : ["schemaVersion", "requestID", "operation", "key"]
            #expect(Set(fields.keys) == expected)
            #expect(
                try JSONDecoder().decode(
                    StorageRequest.self,
                    from: encoded
                ) == request
            )
            let response = try StorageResponse(
                requestID: zeroID,
                operation: operation,
                result   : operation == .read ? .missing : .acknowledged
            )
            try response.validate(matching: request)
            let responseData = try StorageFrameCodec.encode(
                response,
                profile: .v1_1
            )
            let responseFields = try #require(
                JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            )
            #expect(Set(responseFields.keys) == ["schemaVersion", "requestID", "operation", "result"])
            #expect(
                try JSONDecoder().decode(
                    StorageResponse.self,
                    from: responseData
                ) == response
            )
        }
        var fields = requestFields()
        fields["value"] = ["not": "base64"]
        failure(.invalidPayload) {
            _ = try JSONDecoder().decode(
                StorageRequest.self,
                from: json(fields)
            )
        }
        var response = responseFields()
        response["failureCode"] = "invalidPayload"
        failure(.invalidPayload) {
            _ = try JSONDecoder().decode(
                StorageResponse.self,
                from: json(response)
            )
        }
    }

    @Test func decodedSemanticLimitsMatchConstructionAndGenericPayloadCapsStayExact() throws {
        for key in [
            "",
            String(
                repeating: "é",
                count    : 129
            ), "a\0b",
        ] {
            var fields = requestFields()
            fields["key"] = key
            failure(.invalidPayload) {
                _ = try StorageFrameCodec.decodeRequest(
                    json(fields),
                    profile: .v1_1
                )
            }
        }
        var response = responseFields()
        response.merge([
            "result": "value",
            "value": Data(
                repeating: 0,
                count    : 65_537
            ).base64EncodedString(),
        ]) { _, new in new }
        failure(.invalidPayload) {
            _ = try StorageFrameCodec.decodeResponse(
                json(response),
                profile: .v1_1
            )
        }
        let reason = String(
            repeating: "é",
            count    : 2_048
        )
        let failureResponse = try StorageResponse(
            requestID    : requestID,
            operation    : .read,
            result       : .failure,
            failureCode  : .outcomeUnknown,
            failureReason: reason
        )
        #expect(
            try StorageFrameCodec.decodeResponse(
                StorageFrameCodec.encode(
                    failureResponse,
                    profile: .v1_1
                ),
                profile: .v1_1
            ).failureReason == reason
        )
        failure(.invalidPayload) {
            _ = try StorageResponse(
                requestID    : requestID,
                operation    : .read,
                result       : .failure,
                failureCode  : .invalidPayload,
                failureReason: reason + "x"
            )
        }
        let exact = Data(
            repeating: 0,
            count    : 65_536
        )
        _ = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : requestID,
            contractID   : "storage",
            operation    : "write",
            payload      : exact,
            deadline     : Date()
        )
        _ = try ServiceResponse(
            schemaVersion: 1,
            contractID   : "storage",
            operation    : "read",
            payload      : exact
        )
        let excessive = Data(
            repeating: 0,
            count    : 65_537
        )
        failure(.invalidPayload) {
            _ = try ServiceInvocation(
                schemaVersion: 1,
                requestID    : requestID,
                contractID   : "storage",
                operation    : "write",
                payload      : excessive,
                deadline     : Date()
            )
        }
        failure(.invalidPayload) {
            _ = try ServiceResponse(
                schemaVersion: 1,
                contractID   : "storage",
                operation    : "read",
                payload      : excessive
            )
        }
        let invalidUTF8 = Data([255])
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeRequest(
                invalidUTF8,
                profile: .v1_1
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeResponse(
                invalidUTF8,
                profile: .v1_1
            )
        }
        let exactPoison = Data(
            repeating: 255,
            count    : StorageFrameCodec.maximumEncodedBytes
        )
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeRequest(
                exactPoison,
                profile: .v1_1
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try StorageFrameCodec.decodeResponse(
                exactPoison,
                profile: .v1_1
            )
        }
    }
}
