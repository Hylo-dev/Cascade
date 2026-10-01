//
//  FocusRecord.swift
//  StandaloneFocus
//

import CascadeContracts
import Foundation

struct FocusRecord: Codable, Sendable {

    let schemaVersion: Int
    let assignment   : PublicationID
    var session      : FocusSession
    var revision     : UInt64
    var activeToken  : String?
    var receipts     : [FocusReceipt]

    init(
        assignment: PublicationID,
        duration  : TimeInterval
    ) throws {
        schemaVersion   = 1
        self.assignment = assignment
        session         = try FocusSession(duration: duration)
        revision        = 0
        receipts        = []
    }

    mutating func reserveRevision() throws {
        guard revision < UInt64.max else { throw FocusError.revisionExhausted }

        revision += 1
    }

    func validate() throws {
        guard schemaVersion == 1,
              revision > 0,
              receipts.count <= 16,
              Set(receipts.map { $0.request.requestID }).count == receipts.count
        else { throw FocusError.corruptState }

        try session.validate()

        if session.phase == .running {
            guard let activeToken,
                  activeToken.hasPrefix("focus.expiry."),
                  UUID(uuidString: String(activeToken.dropFirst("focus.expiry.".count))) != nil
            else { throw FocusError.corruptState }
        } else if activeToken != nil {
            throw FocusError.corruptState
        }

        var previous: UInt64 = 0
        for receipt in receipts {
            try receipt.request.validate()
            try receipt.outcome.validate()

            guard receipt.request.publicationID == assignment,
                  receipt.request.input.isEmpty,
                  FocusCommand(rawValue: receipt.request.actionID) != nil,
                  receipt.revision > previous,
                  receipt.revision <= revision,
                  receipt.request.observedRevision > 0,
                  receipt.request.observedRevision < receipt.revision
            else { throw FocusError.corruptState }

            switch receipt.outcome {
                case .completed(let payload):
                    guard payload.isEmpty else { throw FocusError.corruptState }

                case .rejected(let failure):
                    guard failure.code == .invalidPayload,
                          failure.reason == "Command unavailable in current phase"
                    else { throw FocusError.corruptState }

                case .outcomeUnknown: throw FocusError.corruptState
            }
            previous = receipt.revision
        }
    }
}
