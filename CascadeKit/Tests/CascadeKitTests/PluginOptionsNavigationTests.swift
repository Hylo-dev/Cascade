//
//  PluginOptionsNavigationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
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

    @Test
    func sourceRefreshKeepsTheLivePageAndRejectsOldAndDismissedControls() throws {
        let rig = try Rig()
        rig.show()
        try rig.widget.openOptions()
        rig.acceptances[0]()
        let page = try #require(rig.presentation?.optionsPage)
        let old = try #require(rig.widget.store.model(PluginNodeID(rawValue: "#stop.first:button")))
        try rig.publish(control: "second")
        #expect(rig.presentation?.optionsPage === page)
        #expect(page.contentRevision == 2)
        try rig.widget.store.press(old)
        #expect(rig.submitted.isEmpty)
        let current = try #require(rig.widget.store.model(PluginNodeID(rawValue: "#stop.second:button")))
        try rig.widget.store.press(current)
        #expect(rig.submitted.count == 1)
        #expect(rig.submitted[0].revision == 2)
        let lease = try #require(rig.presentation?.optionsLeaseID)
        rig.fixture.coordinator.dismissOptions(leaseID: lease)
        try rig.widget.store.press(current)
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
        #expect(rig.presentation?.optionsPage != nil)
        rig.fixture.inventory.entries = []
        rig.fixture.inventory.sendChange()
        let stop = try #require(rig.widget.store.model(PluginNodeID(rawValue: "#stop.second:button")))
        try rig.widget.store.press(stop)
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

    @MainActor
    private final class Rig {

        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let key: PluginPublicationKey
        let host: Host
        var router: PluginSurfaceRouter
        var publisher = PluginPublicationStore()
        var acceptances: [@MainActor @Sendable () -> Void] = []
        var requests: [PluginActionRequest] = []
        var submitted: [PluginActionRequest] = []
        var widget: PluginWidget {
            get throws { try #require(host.widgets.values.first) }
        }
        var presentation: DisplayPresentation? { fixture.surfaces[10]?.presentations.last }

        init(fullscreen: Bool = true) throws {
            let owner = try #require(PluginID(rawValue: "com.example.options"))
            key = PluginPublicationKey(plugin: owner, feature: "test", surface: .widget)
            host = Host(coordinator: fixture.coordinator)
            let manifest = try PluginManifest(
                manifestVersion: 2,
                id             : owner,
                version        : "1.0.0",
                compatibility  : PluginCompatibility(macOS: "15.0", cascadeProtocol: PluginProtocolVersion(major: 2, minimumMinor: 0)),
                execution      : PluginExecution(entryPoint: "Options"),
                sourceApp      : nil,
                requires       : [],
                features       : [PluginFeature(id: "test", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 1)])), actions: ["open", "stop"], supportsFullscreen: fullscreen)],
                resources      : PluginResources(profile: .eventDriven)
            )
            router = PluginSurfaceRouter(host: host, manifests: [manifest], submit: { _ in }, visibility: { _, _ in })
            router = PluginSurfaceRouter(
                host          : host,
                manifests     : [manifest],
                submit        : { [weak self] in self?.submitted.append($0) },
                visibility    : { _, _ in },
                submitAccepted: { [weak self] request, accepted in
                    self?.requests.append(request)
                    self?.acceptances.append(accepted)
                }
            )
            try publish(control: "first")
        }

        func publish(control: String) throws {
            let document = try PluginDocument(
                root         : PluginNode(.button(action: "open"), id: "open", children: [PluginNode(.text("Open"))]),
                optionsRoot  : PluginNode(.button(action: "stop"), id: "stop." + control, children: [PluginNode(.text("Stop"))]),
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
        func capturePluginOptionsOrigin(widgetID: WidgetIdentifier, publicationID: PublicationID, observedRevision: UInt64) -> AddonOptionsOrigin? {
            coordinator.capturePluginOptionsOrigin(widgetID: widgetID, publicationID: publicationID, observedRevision: observedRevision)
        }
        func presentOptions(page: any NotchContextualPage, leaseID: UUID, origin: AddonOptionsOrigin, onDismiss: @escaping @MainActor () -> Void) -> Bool {
            coordinator.presentOptions(page: page, leaseID: leaseID, origin: origin, onDismiss: onDismiss)
        }
        func dismissOptions(leaseID: UUID) { coordinator.dismissOptions(leaseID: leaseID) }
        func present(_ activity: any NotchLiveActivity) {}
        func showNotice(_ notice: any NotchTransientNotice) {}
        func updateNotice(_ notice: any NotchTransientNotice) {}
        func dismissActivity(id: String) {}
    }
}
