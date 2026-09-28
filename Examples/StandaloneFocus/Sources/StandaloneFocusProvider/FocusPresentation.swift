//
//  FocusPresentation.swift
//  StandaloneFocus
//

import CascadeContracts
import Foundation

/// FocusPresentation builds finite widget content. Countdown drawing belongs to the host; no timer task.
enum FocusPresentation {
    static func output(record: FocusRecord, now: Date, completion: InvocationCompletion?, schedule: Bool) throws
        -> ProviderOutput
    {
        let session = record.session
        let label: String
        switch session.phase {
        case .idle: label = "Ready"
        case .running: label = "Focus"
        case .paused: label = "Paused"
        case .completed: label = "Completed"
        case .ended: label = "Ended"
        }
        var children = [try ContentNode.text(label)]
        if let deadline = session.deadline {
            children.append(try .countdown(until: deadline))
        } else if session.phase == .paused || session.phase == .idle {
            let seconds = Int(ceil(session.remaining))
            children.append(try .text(String(format: "%02d:%02d", seconds / 60, seconds % 60)))
        }
        let commands: [FocusCommand]
        switch session.phase {
        case .idle, .completed, .ended: commands = [.start]
        case .running: commands = [.pause, .end]
        case .paused: commands = [.resume, .end]
        }
        for command in commands {
            children.append(try .action(ActionDescriptor(id: command.rawValue, label: command.rawValue.capitalized)))
        }
        let document = try ContentDocument(
            root: .column(children),
            privacy: .publicContent,
            accessibilityLabel: "Standalone focus: \(label)"
        )
        let presentation = try PresentationSet(
            widget: document,
            compactLeading: nil,
            compactTrailing: nil,
            minimal: nil,
            expanded: nil
        )
        // Running content lasts until deadline + one hour; static content for one hour.
        let expiry = try futureDate(max(now, session.deadline ?? now), interval: 3600)
        let publication = try Publication(
            id: record.assignment,
            revision: record.revision,
            kind: .widget,
            content: presentation,
            timeline: nil,
            expiresAt: expiry,
            stalePolicy: .remove
        )
        var operations: [OperationRequest] = []
        if schedule, let deadline = session.deadline, let token = record.activeToken {
            operations = [.schedule(deadline: deadline, eventID: token)]
        }
        return try ProviderOutput(
            schemaVersion: 1,
            publications: [publication],
            operations: operations,
            completion: completion,
            checkpoint: nil
        )
    }
    static func empty(completion: InvocationCompletion? = nil) throws -> ProviderOutput {
        try ProviderOutput(schemaVersion: 1, publications: [], operations: [], completion: completion, checkpoint: nil)
    }
}
