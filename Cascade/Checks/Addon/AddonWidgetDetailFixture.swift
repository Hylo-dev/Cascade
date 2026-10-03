//
//  AddonWidgetDetailFixture.swift
//  Cascade
//

#if DEBUG
import AppKit
import CascadeContracts
import CascadeKit

/// AddonWidgetDetailFixture publishes host-owned values through the common addon
/// bridge. Its brightness is only a number; no display or provider is controlled.
@MainActor
final class AddonWidgetDetailFixture {

    struct Binding {

        let request   : AddonOptionsRequest
        let origin    : AddonOptionsOrigin
        let generation: ConnectionGeneration
        let expiresAt : Date
    }

    static var isRequested: Bool {
        CommandLine.arguments.contains("--preview-addon-widget-detail")
            || CommandLine.arguments.contains("--check-addon-widget-detail")
    }

    let engine: NotchEngine
    private(set) var brightness: Double = 0.6
    private(set) var revision: UInt64 = 1
    private(set) var publicationID: PublicationID
    private(set) var active: Binding?
    private(set) var pending: Binding?
    private(set) var lastFailure: String?
    var defersOpening = false

    private let owner: AddonID
    private let sessionID = UUID()
    private var expiresAt = Date.now.addingTimeInterval(3_600)
    private var checkTask: Task<Void, Never>?
    private var bridge: AddonPresentationBridge?

    init(engine: NotchEngine) throws {
        self.engine = engine
        guard let owner = AddonID(rawValue: "dev.cascade.debug.widget-detail") else {
            throw AddonWidgetDetailChecks.Failure(reason: "Invalid Debug fixture owner")
        }
        self.owner = owner
        publicationID = PublicationID(
            addonID   : owner,
            instanceID: UUID(),
            sessionID : sessionID
        )
        bridge = AddonPresentationBridge(
            engine         : engine,
            onWidgetAction : { [weak self] publicationID, revision, action, origin in
                self?.handleWidgetAction(publicationID, revision: revision, action: action, origin: origin)
            },
            onOptionsAction: { [weak self] leaseID, publicationID, revision, action in
                self?.handleOptionsAction(leaseID, publicationID: publicationID, revision: revision, action: action)
            }
        )
    }

    func start(check: Bool, keepOpen: Bool) {
        do { try publish() }
        catch {
            print("FAIL: addon widget detail fixture publication: \(error)")
            exit(EXIT_FAILURE)
        }
        engine.start()
        engine.open()
        guard check else { return }

        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await AddonWidgetDetailChecks.run(self, keepOpen: keepOpen)
                print("PASS: addon widget detail compiled-app check; ending=\(keepOpen ? "detail-open" : "withdrawn")")
                if !keepOpen { NSApp.terminate(nil) }
            } catch is CancellationError {
                return
            } catch {
                print("FAIL: addon widget detail compiled-app check: \(error)")
                stop()
                engine.stop()
                exit(EXIT_FAILURE)
            }
        }
    }

    func stop() {
        checkTask?.cancel()
        checkTask = nil
        withdraw()
        bridge = nil
    }

    func publish() throws {
        let document = try ContentDocument(
            root: .column([
                .action(action("options", label: "Mock display options ›")),
                .progress(value: brightness),
                .action(action("brightness", label: "Mock brightness \(Int(brightness * 100))% +"))
            ]),
            privacy: .publicContent,
            accessibilityLabel: "Debug mock display widget"
        )
        let publication = try Publication(
            id         : publicationID,
            revision   : revision,
            kind       : .widget,
            content    : PresentationSet(
                widget         : document,
                compactLeading : nil,
                compactTrailing: nil,
                minimal        : nil,
                expanded       : nil
            ),
            timeline   : nil,
            expiresAt  : expiresAt,
            stalePolicy: .remove
        )
        bridge?.apply([publication])
    }

    /// accept uses the exact captured instance, including after deferred work.
    /// Refresh keeps the initial action binding and deadline, while only the
    /// current source revision and bounded document may change.
    @discardableResult
    func accept(_ binding: Binding) -> Bool {
        let presentation = AddonOptionsPresentation(
            request   : binding.request,
            origin    : binding.origin,
            generation: binding.generation,
            expiresAt : binding.expiresAt
        )
        guard bridge?.presentOptions(presentation, onDismiss: { [weak self, origin = binding.origin] in
            guard self?.active?.origin === origin else { return }
            self?.active = nil
        }) == true else { return false }

        active = binding
        pending = nil
        return true
    }

    func refreshSource(refreshDetail: Bool) throws {
        revision &+= 1
        try publish()
        if refreshDetail { try refreshDetailDocument() }
    }

    func refreshDetailDocument() throws {
        guard let initial = active else { return }
        let updated = Binding(
            request: try AddonOptionsRequest(
                publicationID   : publicationID,
                observedRevision: revision,
                actionRequestID : initial.request.actionRequestID,
                leaseID         : initial.request.leaseID,
                document        : detailDocument()
            ),
            origin    : initial.origin,
            generation: initial.generation,
            expiresAt : initial.expiresAt
        )
        guard accept(updated) else {
            throw AddonWidgetDetailChecks.Failure(reason: "Valid same-lease refresh rejected")
        }
    }

    func dismiss(_ binding: Binding) {
        bridge?.dismissOptions(leaseID: binding.request.leaseID, origin: binding.origin)
    }

    func withdraw() {
        pending?.origin.revoke()
        pending = nil
        bridge?.apply([])
    }

    /// replaceWithdrawnSource uses a new identity because a retired publication
    /// cannot be resurrected by a higher revision in the common bridge.
    func replaceWithdrawnSource() throws {
        publicationID = PublicationID(addonID: owner, instanceID: UUID(), sessionID: sessionID)
        revision = 1
        expiresAt = .now.addingTimeInterval(3_600)
        try publish()
        engine.showOrdinaryPage()
        engine.open()
    }

    private func handleWidgetAction(
        _ publicationID: PublicationID,
        revision       : UInt64,
        action         : ActionDescriptor,
        origin         : AddonOptionsOrigin
    ) {
        guard publicationID == self.publicationID, revision == self.revision else { return }

        do {
            switch action.id {
                case "brightness":
                    origin.revoke()
                    brightness = brightness >= 0.9 ? 0.2 : brightness + 0.1
                    try refreshSource(refreshDetail: false)

                case "options":
                    let binding = Binding(
                        request: try AddonOptionsRequest(
                            publicationID   : publicationID,
                            observedRevision: revision,
                            actionRequestID : UUID(),
                            leaseID         : UUID(),
                            document        : detailDocument()
                        ),
                        origin    : origin,
                        generation: ConnectionGeneration(),
                        expiresAt : expiresAt
                    )
                    pending = binding
                    if !defersOpening, !accept(binding) {
                        throw AddonWidgetDetailChecks.Failure(reason: "Visible widget origin rejected")
                    }

                default: origin.revoke()
            }
        } catch {
            lastFailure = String(describing: error)
            print("FAIL: addon widget detail action: \(error)")
        }
    }

    private func handleOptionsAction(
        _ leaseID    : UUID,
        publicationID: PublicationID,
        revision     : UInt64,
        action       : ActionDescriptor
    ) {
        guard let binding = active,
              binding.request.leaseID == leaseID,
              binding.origin.isValid,
              publicationID == self.publicationID,
              revision == self.revision
        else { return }

        do {
            switch action.id {
                case "detail-dim":
                    brightness = 0.25
                    try refreshSource(refreshDetail: true)

                case "detail-refresh": try refreshSource(refreshDetail: true)
                case "detail-withdraw": withdraw()
                default: break
            }
        } catch {
            lastFailure = String(describing: error)
            print("FAIL: addon widget detail control: \(error)")
        }
    }

    private func detailDocument() throws -> ContentDocument {
        try ContentDocument(
            root: .column([
                .row([.symbol("display"), .text("Mock display")]),
                .text("Host-owned Debug data · revision \(revision)"),
                .progress(value: brightness),
                .text("Brightness \(Int(brightness * 100))% · no system settings change"),
                .row([
                    .action(action("detail-dim", label: "Dim mock brightness")),
                    .action(action("detail-refresh", label: "Refresh mock source"))
                ]),
                .action(action("detail-withdraw", label: "Withdraw mock widget"))
            ]),
            privacy: .publicContent,
            accessibilityLabel: "Mock display options"
        )
    }

    private func action(_ id: String, label: String) throws -> ActionDescriptor {
        try ActionDescriptor(id: id, label: label, payload: Data())
    }
}
#endif
