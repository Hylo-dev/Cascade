import Foundation
import CascadeContracts

/// A deliberately tiny example wire grammar, independent of SDK service contracts.
public enum FocusSessionsContract {
    public static let serviceID = "com.example.focus.sessions"
    public static let operation = "read"
    public static let version = "1.0.0"
    public static let maximumPayloadBytes = 256

    public static func scope() throws -> ServiceScope {
        try ServiceScope(featureID: "summary", operation: operation)
    }

    /// Accepts the two literal keys in either order with JSON whitespace and integer tokens.
    /// Escaped key spellings, duplicates, fractions and exponents are intentionally unsupported.
    public static func decode(_ data: Data) throws -> Int {
        guard data.count <= maximumPayloadBytes,
              let text = String(data: data, encoding: .utf8)
        else { throw invalidPayload() }
        let space = #"[ \t\r\n]*"#
        let schema = #""schemaVersion""# + space + ":" + space + "1"
        let count = #""completedSessions""# + space + ":" + space + #"(0|[1-9][0-9]{0,3})"#
        let pattern = #"\A"# + space + #"\{"# + space + "(?:" + schema + space + "," + space + count + "|" + count + space + "," + space + schema + ")" + space + #"\}"# + space + #"\z"#
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              decoded.schemaVersion == 1, (0...1000).contains(decoded.completedSessions)
        else { throw invalidPayload() }
        return decoded.completedSessions
    }

    public static func syntheticResponse() throws -> ServiceResponse {
        try ServiceResponse(schemaVersion: 1, contractID: serviceID, operation: operation,
                            payload: Data(#"{"schemaVersion":1,"completedSessions":3}"#.utf8))
    }

    private struct Payload: Decodable { let schemaVersion: Int; let completedSessions: Int }
    private static func invalidPayload() -> AddonFailure {
        AddonFailure(code: .invalidPayload, reason: "Invalid bounded example sessions payload")
    }
}
