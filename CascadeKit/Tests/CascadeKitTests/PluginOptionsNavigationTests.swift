//
//  PluginOptionsNavigationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginOptionsNavigationTests {

    @Test
    func equalLateAcceptedClicksCannotOpenOverTheLatestClickOrAfterBack() throws {
        let rig = try Rig()
        rig.show()
        try rig.widget.openOptions()
        try rig.widget.openOptions()
        #expect(rig.acceptances.count == 2)
        #expect(rig.requests[0] == rig.requests[1])
        rig.acceptances[0]()
        #expect(rig.presentation?.optionsPage == nil)
        rig.acceptances[1]()
        #expect(rig.presentation?.optionsPage != nil)
        let lease = try #require(rig.presentation?.optionsLeaseID)
        rig.fixture.coordinator.dismissOptions(leaseID: lease)
        rig.acceptances[0]()
        rig.acceptances[1]()
        #expect(rig.presentation?.optionsPage == nil)
        #expect(rig.presentation?.showsWidgets == true)
        rig.fixture.coordinator.stop()
    }

    /// Every button that carries the options action is an opener: a widget with a face for each
    /// size draws one in each face, and the tile shows only one of them.
    @Test
    func everyButtonWithTheOptionsActionOpensThePage() throws {
        let rig = try Rig()
        rig.openers = ["open", "open.large"]
        try rig.publish(control: "first")
        rig.show()
        defer { rig.fixture.coordinator.stop() }
        let store = try rig.widget.store

        #expect(store.optionsButtons.map(\.id.rawValue) == ["#open:button", "#open.large:button"])
        #expect(store.isOptionsButton(PluginNodeID(rawValue: "#open.large:button")))
        #expect(!store.isOptionsButton(PluginNodeID(rawValue: "#compact:button")))

        for (index, node) in ["#open:button", "#open.large:button"].enumerated() {
            let opener = try #require(store.model(PluginNodeID(rawValue: node)))
            store.press(opener)
            #expect(rig.acceptances.count == index + 1)
            #expect(rig.requests[index].node.rawValue == node)
            rig.acceptances[index]()
            #expect(rig.presentation?.optionsPage != nil)
            rig.fixture.coordinator.dismissOptions(leaseID: try #require(rig.presentation?.optionsLeaseID))
            #expect(rig.presentation?.optionsPage == nil)
        }

        let compact = try #require(store.model(PluginNodeID(rawValue: "#compact:button")))
        store.press(compact)
        #expect(rig.acceptances.count == 2)
        #expect(rig.submitted.last?.node.rawValue == "#compact:button")
    }

    @Test
    func sourceRefreshKeepsTheLivePageAndRejectsOldAndDismissedControls() throws {
        let rig = try Rig()
        rig.show()
        try rig.widget.openOptions()
        rig.acceptances[0]()
        let page = try #require(rig.presentation?.optionsPage)
        let oldAction = try #require(renderedButton(in: content(of: page)))
        try rig.publish(control: "second")
        #expect(rig.presentation?.optionsPage === page)
        #expect(page.contentRevision == 2)
        oldAction()
        #expect(rig.submitted.isEmpty)
        let currentAction = try #require(renderedButton(in: content(of: page)))
        currentAction()
        #expect(rig.submitted.count == 1)
        #expect(rig.submitted[0].revision == 2)
        let lease = try #require(rig.presentation?.optionsLeaseID)
        rig.fixture.coordinator.dismissOptions(leaseID: lease)
        currentAction()
        #expect(rig.submitted.count == 1)
        rig.fixture.coordinator.stop()
    }

    @Test
    func withdrawalAndDisplayLossRevokePendingAndMountedOptions() throws {
        let rig = try Rig()
        rig.show()
        try rig.widget.openOptions()
        let withdrawal = rig.publisher.withdraw(rig.key)
        rig.router.apply([try #require(withdrawal)], rejected: [])
        rig.acceptances[0]()
        #expect(rig.presentation?.optionsPage == nil)
        try rig.publish(control: "second")
        try rig.widget.openOptions()
        rig.acceptances[1]()
        let page = try #require(rig.presentation?.optionsPage)
        let action = try #require(renderedButton(in: content(of: page)))
        rig.fixture.inventory.entries = []
        rig.fixture.inventory.sendChange()
        action()
        #expect(rig.submitted.isEmpty)
        rig.fixture.coordinator.stop()
    }

    @Test
    func hiddenAndUngrantedWidgetsCannotSubmitAnOpeningAction() throws {
        let rig = try Rig()
        rig.fixture.coordinator.start()
        try rig.widget.openOptions()
        #expect(rig.acceptances.isEmpty)
        rig.fixture.coordinator.stop()
        let ungranted = try Rig(fullscreen: false)
        ungranted.show()
        try ungranted.widget.openOptions()
        #expect(ungranted.acceptances.isEmpty)
        ungranted.fixture.coordinator.stop()
    }

    @Test
    func aRetainedRenderedButtonCannotBorrowAReopenedPagesOrigin() throws {
        let rig = try Rig()
        rig.show()
        defer { rig.fixture.coordinator.stop() }
        try rig.widget.openOptions()
        rig.acceptances[0]()
        let oldPage = try #require(rig.presentation?.optionsPage)
        let model = try #require(rig.widget.store.optionsRoot)
        let oldAction = try #require(renderedButton(in: content(of: oldPage)))
        let lease = try #require(rig.presentation?.optionsLeaseID)
        rig.fixture.coordinator.dismissOptions(leaseID: lease)
        oldAction()
        #expect(rig.submitted.isEmpty)

        try rig.widget.openOptions()
        rig.acceptances[1]()
        let currentPage = try #require(rig.presentation?.optionsPage)
        #expect(currentPage !== oldPage)
        #expect(try rig.widget.store.optionsRoot === model)
        #expect(try rig.widget.store.revision == 1)
        oldAction()
        #expect(rig.submitted.isEmpty)
        let currentAction = try #require(renderedButton(in: content(of: currentPage)))
        currentAction()
        #expect(rig.submitted.count == 1)
        rig.nativeDeliveries.last?()
        #expect(rig.delivered.count == 1)
    }

    @Test
    func compactDeliveryRemainsIndependentOfOptionsRevocation() throws {
        let rig = try Rig()
        rig.show()
        defer { rig.fixture.coordinator.stop() }
        try rig.widget.openOptions()
        rig.acceptances[0]()
        let widget = try rig.widget
        let model = try #require(widget.store.model(PluginNodeID(rawValue: "#compact:button")))
        let cupAction = try #require(renderedButton(in: PluginNodeContent(model: model, store: widget.store).body))
        cupAction()
        let delivery = try #require(rig.nativeDeliveries.first)
        rig.fixture.coordinator.dismissOptions(leaseID: try #require(rig.presentation?.optionsLeaseID))
        delivery()
        #expect(rig.delivered.count == 1)
        #expect(rig.delivered.first?.node.rawValue == "#compact:button")
    }

    @Test
    func aRetainedRenderedToggleCannotChangeStateAfterBackAndReopen() throws {
        let rig = try Rig()
        try rig.publish(control: "toggle", toggle: true)
        rig.show()
        defer { rig.fixture.coordinator.stop() }
        try rig.widget.openOptions()
        rig.acceptances[0]()
        let oldPage = try #require(rig.presentation?.optionsPage)
        let model = try #require(rig.widget.store.optionsRoot)
        let oldSetter = try #require(renderedControl(in: content(of: oldPage), as: ((Bool, Transaction) -> Void).self))
        rig.fixture.coordinator.dismissOptions(leaseID: try #require(rig.presentation?.optionsLeaseID))
        try rig.widget.openOptions()
        rig.acceptances[1]()
        oldSetter(true, Transaction())
        #expect(rig.submitted.isEmpty)
        #expect(model.optimistic == nil)
        let page = try #require(rig.presentation?.optionsPage)
        let currentSetter = try #require(renderedControl(in: content(of: page), as: ((Bool, Transaction) -> Void).self))
        currentSetter(true, Transaction())
        #expect(rig.submitted.count == 1)
        #expect(model.optimistic == .bool(true))
        rig.nativeDeliveries.last?()
        #expect(rig.delivered.count == 1)
    }

    @Test(arguments: ["back", "reopen", "withdrawal", "display", "source", "revision", "termination"])
    func acceptedDetailIsRevalidatedImmediatelyBeforeItsNativeEffect(revocation: String) throws {
        let rig = try Rig()
        rig.show()
        defer { rig.fixture.coordinator.stop() }
        try rig.widget.openOptions()
        rig.acceptances[0]()
        let page = try #require(rig.presentation?.optionsPage)
        let action = try #require(renderedButton(in: content(of: page)))
        action()
        #expect(rig.submitted.count == 1)
        let lateDelivery = try #require(rig.nativeDeliveries.first)
        #expect(rig.delivered.isEmpty)
        switch revocation {
            case "back", "reopen":
                rig.fixture.coordinator.dismissOptions(leaseID: try #require(rig.presentation?.optionsLeaseID))
                if revocation == "reopen" {
                    try rig.widget.openOptions()
                    rig.acceptances[1]()
                    #expect(rig.requests[0] == rig.requests[1])
                }
            case "withdrawal":
                let withdrawal = rig.publisher.withdraw(rig.key)
                rig.router.apply([try #require(withdrawal)], rejected: [])
            case "display":
                rig.fixture.inventory.entries = []
                rig.fixture.inventory.sendChange()
            case "source":
                rig.fixture.coordinator.unregisterWidget(id: try rig.widget.id)
            case "revision":
                try rig.publish(control: "second")
            case "termination":
                rig.fixture.coordinator.stop()
            default:
                Issue.record("Unknown revocation")
        }
        lateDelivery()
        #expect(rig.delivered.isEmpty)
        if revocation == "reopen" {
            let currentPage = try #require(rig.presentation?.optionsPage)
            let currentAction = try #require(renderedButton(in: content(of: currentPage)))
            currentAction()
            rig.nativeDeliveries.last?()
            #expect(rig.delivered.count == 1)
            #expect(rig.submitted[0] == rig.submitted[1])
        }
    }

    private func content(of page: any NotchContextualPage) -> AnyView {
        page.makeContentView(in: .init(availableSize: CGSize(width: 400, height: 220)))
    }

    /// renderedButton extracts the action from the page's actual SwiftUI Button.
    /// A direct store call would miss the retained control's captured page identity.
    private func renderedButton(in value: Any) -> (@MainActor () -> Void)? {
        renderedControl(in: value, as: (@MainActor () -> Void).self)
    }

    /// renderedControl evaluates the real nominal renderer, including its page scope.
    /// Reflection is bounded and test-only. A Toggle stores its original Binding setter
    /// behind a location box; extracting it invokes the same closure as rendered input.
    private func renderedControl<Value>(
        in value: Any,
        as type : Value.Type,
        depth   : Int = 0
    ) -> Value? {
        guard depth < 40 else { return nil }
        if let control = value as? Value { return control }
        if let view = value as? PluginDocumentView { return renderedControl(in: view.body, as: type, depth: depth + 1) }
        if let view = value as? PluginNodeView { return renderedControl(in: view.body, as: type, depth: depth + 1) }
        if let view = value as? PluginModifiedView { return renderedControl(in: view.body, as: type, depth: depth + 1) }
        if let view = value as? PluginNodeContent { return renderedControl(in: view.body, as: type, depth: depth + 1) }
        for child in Mirror(reflecting: value).children {
            if let control = renderedControl(in: child.value, as: type, depth: depth + 1) { return control }
        }
        return nil
    }

    @MainActor
    private final class Rig {

        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let key: PluginPublicationKey
        let host: Host
        let feature: PluginFeature
        var router: PluginSurfaceRouter
        var publisher = PluginPublicationStore()
        var acceptances: [@MainActor @Sendable () -> Void] = []
        var requests: [PluginActionRequest] = []
        var submitted: [PluginActionRequest] = []
        var nativeDeliveries: [@MainActor () -> Void] = []
        var delivered: [PluginActionRequest] = []
        var openers = ["open"]
        var widget: PluginWidget {
            get throws { try #require(host.widgets.values.first) }
        }
        var presentation: DisplayPresentation? { fixture.surfaces[10]?.presentations.last }

        init(fullscreen: Bool = true) throws {
            let owner = try #require(PluginID(rawValue: "com.example.options"))
            key = PluginPublicationKey(plugin: owner, feature: "test", surface: .widget)
            host = Host(coordinator: fixture.coordinator)
            feature = try PluginFeature(id: "test", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 1)])), actions: ["open", "stop", "compact"], supportsFullscreen: fullscreen)
            let manifest = try PluginManifest(
                manifestVersion: 2,
                id             : owner,
                version        : "1.0.0",
                compatibility  : PluginCompatibility(macOS: "15.0", cascadeProtocol: PluginProtocolVersion(major: 2, minimumMinor: 0)),
                execution      : PluginExecution(entryPoint: "Options"),
                sourceApp      : nil,
                requires       : [],
                features       : [feature],
                resources      : PluginResources(profile: .eventDriven)
            )
            router = PluginSurfaceRouter(host: host, manifests: [manifest], submit: { _ in }, visibility: { _, _ in })
            router = PluginSurfaceRouter(
                host          : host,
                manifests     : [manifest],
                submit        : { [weak self] request in
                    guard let self, PluginActionAuthorizer.event(for: request, entry: publisher[key], feature: feature) != nil else { return }
                    submitted.append(request)
                    nativeDeliveries.append { [weak self] in self?.delivered.append(request) }
                },
                visibility    : { _, _ in },
                submitAccepted: { [weak self] request, accepted in
                    guard let self, PluginActionAuthorizer.event(for: request, entry: publisher[key], feature: feature) != nil else { return }
                    if request.node.rawValue.hasPrefix("#open") {
                        requests.append(request)
                        acceptances.append { accepted {} }
                    } else {
                        submitted.append(request)
                        nativeDeliveries.append { [weak self] in accepted { self?.delivered.append(request) } }
                    }
                }
            )
            try publish(control: "first")
        }

        func publish(control: String, toggle: Bool = false) throws {
            let document = try PluginDocument(
                root         : PluginNode(.hStack(alignment: .center, spacing: 4), children: [
                    PluginNode(.button(action: "compact"), id: "compact", children: [PluginNode(.text("Cup"))]),
                ] + openers.map { PluginNode(.button(action: "open"), id: $0, children: [PluginNode(.text("Open"))]) }),
                optionsRoot  : PluginNode(toggle ? .toggle(isOn: false, action: "stop") : .button(action: "stop"), id: "stop." + control, children: [PluginNode(.text("Stop"))]),
                optionsAction: "open"
            )
            let change = publisher.apply(document, staleAfter: nil, for: key, at: .now)
            router.apply([try #require(change)], rejected: [])
        }

        func show() {
            fixture.coordinator.start()
            fixture.coordinator.requestExpansion(on: 10, activityID: nil)
        }
    }

    /// Host forwards to the real coordinator; only the broker's asynchronous
    /// acceptance boundary is delayed so the tests can drive its ordering.
    @MainActor
    private final class Host: PluginSurfaceHosting {

        let coordinator: NotchDisplayCoordinator
        var widgets: [WidgetIdentifier: PluginWidget] = [:]

        init(coordinator: NotchDisplayCoordinator) { self.coordinator = coordinator }
        func register(_ widget: any NotchWidget) {
            if let plugin = widget as? PluginWidget { widgets[widget.id] = plugin }
            coordinator.register(widget)
        }
        func unregisterWidget(id: WidgetIdentifier) { widgets[id] = nil; coordinator.unregisterWidget(id: id) }
        func captureOptionsOrigin(widgetID: WidgetIdentifier, observedRevision: UInt64) -> PluginOptionsOrigin? {
            coordinator.captureOptionsOrigin(widgetID: widgetID, observedRevision: observedRevision)
        }
        func presentOptions(page: any NotchContextualPage, leaseID: UUID, origin: PluginOptionsOrigin, onDismiss: @escaping @MainActor () -> Void) -> Bool {
            coordinator.presentOptions(page: page, leaseID: leaseID, origin: origin, onDismiss: onDismiss)
        }
        func dismissOptions(leaseID: UUID) { coordinator.dismissOptions(leaseID: leaseID) }
        func showNotice(_ notice: any NotchTransientNotice) {}
        func updateNotice(_ notice: any NotchTransientNotice) {}
        func dismissActivity(id: String) {}
        func present(_ activity: any NotchLiveActivity) {}
        func endActivity(id: String) {}
        func showDetail(
            _ page      : any NotchContextualPage,
            on displayID: CGDirectDisplayID?,
            onDismiss   : @escaping @MainActor () -> Void,
            onPresented : @escaping @MainActor (Bool) -> Void
        ) -> Bool {
            coordinator.showDetail(page, on: displayID, onDismiss: onDismiss, onPresented: onPresented)
        }
        func dismissDetail(id: String) { coordinator.dismissDetail(id: id) }
    }
}
