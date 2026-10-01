//
//  FocusStateCodec.swift
//  StandaloneFocus
//

import CascadeContracts
import Foundation

/// FocusStateCodec treats keyed storage as the sole authority; ProviderOutput.checkpoint is never used.
enum FocusStateCodec {

    static let maximumBytes = 16_384

    static func decode(_ data: Data) throws -> FocusRecord {
        guard data.count <= maximumBytes else { throw FocusError.corruptState }

        do {
            // Reject unknown fields as well as missing required fields through Codable.
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(json.keys).isSubset(of: [
                      "schemaVersion", "assignment", "session", "revision", "activeToken", "receipts",
                  ]),
                  let session = json["session"] as? [String: Any],
                  Set(session.keys).isSubset(of: ["phase", "duration", "remaining", "deadline", "timerID"]),
                  validAssignment(json["assignment"]),
                  let receipts = json["receipts"] as? [[String: Any]],
                  receipts.count <= 16,
                  receipts.allSatisfy({ receipt in
                      Set(receipt.keys) == ["request", "outcome", "revision"]
                          && validRejectedFailure(receipt["outcome"])
                          && (receipt["request"] as? [String: Any]).map {
                              validAssignment($0["publicationID"])
                          } == true
                  })
            else { throw FocusError.corruptState }

            let record = try JSONDecoder().decode(FocusRecord.self, from: data)
            try record.validate()

            return record
        } catch { throw FocusError.corruptState }
    }

    // ActionOutcome closes its own fields, but the public AddonFailure decoder
    // tolerates extras. This durable schema closes that last nested object itself.
    private static func validRejectedFailure(_ value: Any?) -> Bool {
        guard let outcome = value as? [String: Any] else { return false }
        guard let rejectedValue = outcome["rejected"] else { return true }
        guard let rejected = rejectedValue as? [String: Any],
              let failure = rejected["reason"] as? [String: Any]
        else { return false }

        return Set(failure.keys) == ["code", "reason"]
    }

    private static func validAssignment(_ value: Any?) -> Bool {
        guard let fields = value as? [String: Any] else { return false }

        return Set(fields.keys) == ["addonID", "instanceID", "sessionID"]
    }

    static func encode(_ record: FocusRecord) throws -> Data {
        try record.validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(record)
        guard data.count <= maximumBytes else { throw FocusError.corruptState }

        return data
    }
}
