//
//  ServiceInvocationReply.swift
//  CascadeKit
//

import Foundation

/// ServiceInvocationResult is the outcome an invocation reply carries; refusal
/// means this exchange caused no new dispatch. A retained logical request may
/// already have run; refusal is not the SDK's rejected-before-handoff proof.
public enum ServiceInvocationResult: Equatable, Sendable {
    case completed(ServiceResponse)
    case refused(code: AddonFailure.Code, reason: String)
    case outcomeUnknown
}

/// ServiceInvocationReply is a correlated reply with exactly one result, without
/// null or cross-result fields.
public struct ServiceInvocationReply: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let contractID: String
    public let operation: String
    public let result: ServiceInvocationResult

    public init(
        schemaVersion: Int = 1,
        requestID: UUID,
        contractID: String,
        operation: String,
        result: ServiceInvocationResult
    ) throws {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.contractID = contractID
        self.operation = operation
        self.result = result
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let discriminator = try values.decode(String.self, forKey: .result)
        var allowed: Set<String> = ["schemaVersion", "requestID", "contractID", "operation", "result"]
        switch discriminator {
        case "completed": allowed.insert("response")
        case "refused": allowed.formUnion(["failureCode", "failureReason"])
        case "outcomeUnknown": break
        default: throw AddonFailure(code: .invalidPayload, reason: "Unknown service result")
        }
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == allowed,
            "Invalid service reply fields"
        )
        let result: ServiceInvocationResult
        switch discriminator {
        case "completed": result = .completed(try values.decode(ServiceResponse.self, forKey: .response))
        case "refused":
            let rawCode = try values.decode(String.self, forKey: .failureCode)
            guard let code = AddonFailure.Code(rawValue: rawCode) else {
                throw AddonFailure(code: .invalidPayload, reason: "Unknown service failure code")
            }
            result = .refused(code: code, reason: try values.decode(String.self, forKey: .failureReason))
        default: result = .outcomeUnknown // Closed discriminator checked above.
        }
        try self.init(
            schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
            requestID: values.decode(UUID.self, forKey: .requestID),
            contractID: values.decode(String.self, forKey: .contractID),
            operation: values.decode(String.self, forKey: .operation),
            result: result
        )
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1 && ContractValidation.identifier(contractID) && ContractValidation.identifier(operation),
            "Invalid service reply"
        )
        switch result {
        case .completed(let response): try response.validate()
        case .refused(let code, let reason):
            try ContractValidation.require(code != .outcomeUnknown, "Refused result cannot carry outcomeUnknown")
            // Validate original bytes before any truncating AddonFailure initializer.
            try ContractValidation.require(
                !reason.isEmpty && reason.utf8.count <= ServiceFrameCodec.maximumFailureReasonBytes,
                "Invalid service failure reason"
            )
        case .outcomeUnknown: break
        }
    }

    public func validate(matching request: ServiceInvocationRequest) throws {
        try validate()
        try request.validate()
        let invocation = request.invocation
        try ContractValidation.require(
            requestID == invocation.requestID && contractID == invocation.contractID && operation == invocation.operation,
            "Service reply request mismatch"
        )
        if case .completed(let response) = result {
            let completion = InvocationCompletion.service(requestID: requestID, response: response)
            try completion.validateCorrelation(.service(
                requestID: invocation.requestID,
                contractID: invocation.contractID,
                operation: invocation.operation
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(requestID, forKey: .requestID)
        try values.encode(contractID, forKey: .contractID)
        try values.encode(operation, forKey: .operation)
        switch result {
        case .completed(let response):
            try values.encode("completed", forKey: .result)
            try values.encode(response, forKey: .response)
        case .refused(let code, let reason):
            try values.encode("refused", forKey: .result)
            try values.encode(code, forKey: .failureCode)
            try values.encode(reason, forKey: .failureReason)
        case .outcomeUnknown: try values.encode("outcomeUnknown", forKey: .result)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, requestID, contractID, operation, result, response, failureCode, failureReason
    }
}
