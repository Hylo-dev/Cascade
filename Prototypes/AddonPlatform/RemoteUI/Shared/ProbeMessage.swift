//
//  ProbeMessage.swift
//  Cascade Addon Platform Probe
//

import Foundation

/// ProbeBootstrap carries only a fresh endpoint, never business requests or grants.
@objc(ProbeBootstrap)
protocol ProbeBootstrap {
    func connect(to endpoint: NSXPCListenerEndpoint)
}

@objc(ProbeEventReceiver)
protocol ProbeEventReceiver {
    func receive(_ data: Data, reply: @escaping (Data) -> Void)
}

/// ProbeChannel keeps the experiment independent of production SDK types.
@objc(ProbeChannel)
protocol ProbeChannel {
    func request(_ data: Data, reply: @escaping (Data) -> Void)
}

struct ProbeRequest: Codable {
    let requestID: UUID
    let operation: String
    let payload: String
}

struct ProbeResponse: Codable {
    let requestID: UUID
    let providerPID: Int32
    let value: String
    var observations: [String: Bool]? = nil
}

enum ProbeCounterAction: String, Codable {
    case initial
    case increment
    case reset
}

struct ProbeCounterEvent: Codable {
    let sessionID: UUID
    let sequence: Int
    let action: ProbeCounterAction
    let count: Int
}

struct ProbeCounterAck: Codable {
    let sessionID: UUID
    let sequence: Int
    let accepted: Bool
    let terminal: Bool
}

struct ProbeCounterReducer {
    static let maximumBytes = 1_024
    static let maximumActions = 1_000
    static let maximumCount = 1_000

    let sessionID: UUID
    private(set) var isTerminal = false
    private var nextSequence = 0
    private var actionCount = 0
    private var count = 0

    mutating func accept(_ data: Data) -> ProbeCounterAck? {
        guard !isTerminal else { return nil }
        guard data.count <= Self.maximumBytes,
              let event = try? JSONDecoder().decode(ProbeCounterEvent.self, from: data) else {
            isTerminal = true
            return nil
        }

        let valid: Bool
        if nextSequence == 0 {
            valid = event.sessionID == sessionID && event.sequence == 0
                && event.action == .initial && event.count == 0
        } else {
            let transitionValid: Bool
            switch event.action {
            case .initial:
                transitionValid = false
            case .increment:
                transitionValid = count < Self.maximumCount && event.count == count + 1
            case .reset:
                transitionValid = event.count == 0
            }
            valid = event.sessionID == sessionID && event.sequence == nextSequence
                && actionCount < Self.maximumActions && transitionValid
        }

        guard valid else {
            isTerminal = true
            return ProbeCounterAck(sessionID: sessionID, sequence: event.sequence,
                                   accepted: false, terminal: true)
        }
        count = event.count
        nextSequence += 1
        if event.action != .initial { actionCount += 1 }
        return ProbeCounterAck(sessionID: sessionID, sequence: event.sequence,
                               accepted: true, terminal: false)
    }
}

enum ProbeIdentity {
    static let point = "hylo.Cascade.AddonSceneProbe.provider"
    static let provider = "hylo.Cascade.AddonSceneProbeContainer.Provider"
    static let host = "hylo.Cascade.AddonSceneProbe"
    static let team = "A6A5HQL6K4"

    static func requirement(identifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
    }
}
