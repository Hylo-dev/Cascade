//
//  ProbeProvider.swift
//  Cascade Addon Platform Probe
//

import ExtensionFoundation
import ExtensionKit
import SwiftUI
import Foundation

/// ProbeConfiguration authenticates callers before exposing the fixed probe API.
struct ProbeConfiguration: AppExtensionConfiguration {
    nonisolated func accept(connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(ProbeIdentity.requirement(identifier: ProbeIdentity.host))
        connection.exportedInterface = NSXPCInterface(with: ProbeBootstrap.self)
        connection.exportedObject = ProbeBootstrapService()
        connection.resume()
        return true
    }
}

final class ProbeBootstrapService: NSObject, ProbeBootstrap {
    private var channel: NSXPCConnection?

    func connect(to endpoint: NSXPCListenerEndpoint) {
        guard ProbeChannelGate.shared.claim() else { return }
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        channel = connection
        connection.setCodeSigningRequirement(ProbeIdentity.requirement(identifier: ProbeIdentity.host))
        connection.exportedInterface = NSXPCInterface(with: ProbeChannel.self)
        connection.exportedObject = ProbeService(connection: connection)
        connection.remoteObjectInterface = NSXPCInterface(with: ProbeEventReceiver.self)
        connection.interruptionHandler = { ProbeCounterModel.deactivateFromChannel() }
        connection.invalidationHandler = { ProbeCounterModel.deactivateFromChannel() }
        connection.resume()
    }
}

final class ProbeChannelGate: @unchecked Sendable {
    static let shared = ProbeChannelGate()
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

final class ProbeService: NSObject, ProbeChannel {
    private let subscriptionGate = ProbeChannelGate()
    private weak var connection: NSXPCConnection?

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func request(_ data: Data, reply: @escaping (Data) -> Void) {
        guard data.count <= ProbeCounterReducer.maximumBytes,
              let request = try? JSONDecoder().decode(ProbeRequest.self, from: data),
              ["echo", "subscribe"].contains(request.operation) else {
            reply(Data())
            return
        }
        let response = ProbeResponse(requestID: request.requestID, providerPID: getpid(), value: request.payload)
        guard request.operation == "subscribe" else {
            reply((try? JSONEncoder().encode(response)) ?? Data())
            return
        }
        guard subscriptionGate.claim(),
              let sessionID = UUID(uuidString: request.payload), let connection,
              let receiver = connection.remoteObjectProxyWithErrorHandler({ _ in
                  ProbeCounterModel.deactivateFromChannel()
              }) as? ProbeEventReceiver else {
            reply(Data())
            return
        }
        Task { @MainActor in
            ProbeCounterModel.shared.activate(sessionID: sessionID, receiver: receiver) { accepted in
                reply(accepted ? ((try? JSONEncoder().encode(response)) ?? Data()) : Data())
            }
        }
    }
}

@MainActor
final class ProbeCounterModel: ObservableObject {
    static let shared = ProbeCounterModel()

    @Published private(set) var count = 0
    @Published private(set) var enabled = false
    private var sessionID: UUID?
    private var receiver: ProbeEventReceiver?
    private var nextSequence = 0
    private var actionCount = 0
    private var inFlight = false
    private var failed = false
    private var activationCompletion: ((Bool) -> Void)?
    private let deliverAcknowledgement: (@escaping @MainActor () -> Void) -> Void

    init(deliverAcknowledgement: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
        Task { @MainActor in action() }
    }) {
        self.deliverAcknowledgement = deliverAcknowledgement
    }

    var canIncrement: Bool { enabled && count < ProbeCounterReducer.maximumCount }

    nonisolated static func deactivateFromChannel() {
        Task { @MainActor in shared.deactivateFromChannel() }
    }

    func deactivateFromChannel() {
        failClosed()
    }

    func activate(sessionID: UUID, receiver: ProbeEventReceiver,
                  completion: @escaping (Bool) -> Void) {
        guard self.sessionID == nil, !failed, !inFlight else { completion(false); return }
        self.sessionID = sessionID
        self.receiver = receiver
        activationCompletion = completion
        count = 0
        nextSequence = 0
        actionCount = 0
        send(.initial, count: 0)
    }

    func increment() {
        guard canIncrement else { return }
        send(.increment, count: count + 1)
    }

    func reset() {
        guard enabled else { return }
        send(.reset, count: 0)
    }

    private func send(_ action: ProbeCounterAction, count proposedCount: Int) {
        guard let sessionID, let receiver, !inFlight,
              action == .initial || actionCount < ProbeCounterReducer.maximumActions,
              let data = try? JSONEncoder().encode(ProbeCounterEvent(
                  sessionID: sessionID, sequence: nextSequence, action: action, count: proposedCount
              )), data.count <= ProbeCounterReducer.maximumBytes else {
            failClosed()
            return
        }
        let sequence = nextSequence
        inFlight = true
        enabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.inFlight, self.nextSequence == sequence else { return }
            self.failClosed()
        }
        let deliverAcknowledgement = self.deliverAcknowledgement
        receiver.receive(data) { [weak self] ackData in
            deliverAcknowledgement {
                guard let self else { return }
                guard self.inFlight, self.sessionID == sessionID,
                      self.nextSequence == sequence else { return }
                guard ackData.count <= ProbeCounterReducer.maximumBytes,
                      let ack = try? JSONDecoder().decode(ProbeCounterAck.self, from: ackData),
                      ack.sessionID == sessionID, ack.sequence == sequence,
                      ack.accepted, !ack.terminal else {
                    self.failClosed()
                    return
                }
                self.count = proposedCount
                self.nextSequence += 1
                if action != .initial { self.actionCount += 1 }
                self.inFlight = false
                self.enabled = self.actionCount < ProbeCounterReducer.maximumActions
                if action == .initial { self.finishActivation(true) }
            }
        }
    }

    private func failClosed() {
        guard !failed else { return }
        failed = true
        enabled = false
        inFlight = false
        receiver = nil
        sessionID = nil
        finishActivation(false)
    }

    private func finishActivation(_ accepted: Bool) {
        let completion = activationCompletion
        activationCompletion = nil
        completion?(accepted)
    }
}

#if !PROBE_COUNTER_TESTING
@main
#endif
struct ProbeProvider: AppExtension {
    init() {
        NSLog("Cascade probe provider bundle=%@", Bundle.main.bundleURL.path)
    }
    @MainActor var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            PrimitiveAppExtensionScene(id: "main", content: { ProbeScene() },
                onConnection: { ProbeConfiguration().accept(connection: $0) }),
            configuration: ProbeConfiguration()
        )
    }
}

/// Pure SwiftUI UI is instantiated inside the extension, never inside the host.
struct ProbeScene: View {
    @ObservedObject private var model = ProbeCounterModel.shared
    var body: some View {
        VStack(spacing: 12) {
            Text("Cascade — scena remota").font(.headline)
            Text("Conteggio: \(model.count)")
            Button("Incrementa") { model.increment() }
                .disabled(!model.canIncrement)
            Menu("Menu di prova") {
                Button("Azzera") { model.reset() }
            }
            .disabled(!model.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.9))
        .foregroundStyle(.white)
    }
}
