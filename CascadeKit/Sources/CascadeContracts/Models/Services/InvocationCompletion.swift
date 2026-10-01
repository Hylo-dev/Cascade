//
//  InvocationCompletion.swift
//  CascadeKit
//

import Foundation

/// InvocationCompletion correlates one final result independently of state publication.
public enum InvocationCompletion: Codable, Equatable, Sendable {

    case action (requestID: UUID, outcome: ActionOutcome)
    case service(requestID: UUID, response: ServiceResponse)

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            values.allKeys.count == 1,
            "Completion requires exactly one discriminator"
        )
        guard let discriminator = values.allKeys.first else {
            throw AddonFailure(code: .invalidPayload, reason: "Missing completion")
        }

        let fields = try values.nestedContainer(keyedBy: WireKey.self, forKey: discriminator)
        let allowed: Set<String>
        switch discriminator.stringValue {
            case "action" : allowed = ["requestID", "outcome"]
            case "service": allowed = ["requestID", "response"]
            default       : throw AddonFailure(code: .invalidPayload, reason: "Unknown discriminator")
        }
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == allowed,
            "Invalid result fields"
        )

        let payload   = try values.nestedContainer(keyedBy: PayloadKeys.self, forKey: discriminator)
        let requestID = try payload.decode(UUID.self, forKey: .requestID)
        switch discriminator.stringValue {
            case "action":
                self = .action(
                    requestID: requestID,
                    outcome  : try payload.decode(ActionOutcome.self, forKey: .outcome)
                )

            case "service":
                self = .service(
                    requestID: requestID,
                    response : try payload.decode(ServiceResponse.self, forKey: .response)
                )

            default: throw AddonFailure(code: .invalidPayload, reason: "Unknown completion")
        }

        try validate()
    }

    public func validate() throws {
        switch self {
            case .action(_, let outcome)  : try outcome.validate()
            case .service(_, let response): try response.validate()
        }
    }

    private enum PayloadKeys: String, CodingKey {

        case requestID, outcome, response
    }

    public func validateCorrelation(_ expected: CompletionExpectation?) throws {
        switch (self, expected) {
            case (.action(let actual, _), .action(let expected)):
                try ContractValidation.require(
                    actual == expected,
                    "Action result request ID mismatch"
                )

            case (.service(let actual, let response), .service(let expected, let contract, let operation)):
                try ContractValidation.require(
                    actual == expected && response.contractID == contract && response.operation == operation,
                    "Service response request mismatch"
                )

            default:
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Invocation result kind mismatch"
                )
        }
    }
}
