//
//  PluginSurfaceRouterTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct PluginSurfaceRouterTests {

    private let clock = PluginID(rawValue: "com.cascade.clock")!

    private var widgetKey: PluginPublicationKey {
        PluginPublicationKey(plugin: clock, feature: "time", surface: .widget)
    }

    private var widgetID: WidgetIdentifier {
        WidgetIdentifier("plugin:com.cascade.clock/time")
    }

    private var alarmKey: PluginPublicationKey {
        PluginPublicationKey(plugin: clock, feature: "alarm", surface: .widget)
    }

    private var mixerKey: PluginPublicationKey {
        PluginPublicationKey(plugin: clock, feature: "mixer", surface: .widget)
    }

    private var detailKey: PluginPublicationKey {
        PluginPublicationKey(plugin: clock, feature: "mixer", surface: .detail)
    }

    private var detailID: String {
        "plugin-detail:com.cascade.clock/mixer"
    }

    /// Rig is a router over a recording host, with what they submitted and reported.
    @MainActor
    final class Rig {

        let host      = RecordingSurfaceHost()
        var submitted : [PluginActionRequest] = []
        var visibility: [(Bool, PluginPublicationKey)] = []
        var surfaces  : PluginSurfaceRouter!
    }

    private func rig(placedByDefault: Set<PluginID> = []) throws -> Rig {
        let rig      = Rig()
        let manifest = try PluginManifest(
            manifestVersion: 2,
            id             : clock,
            version        : "1.0.0",
            compatibility  : PluginCompatibility(macOS: "15.0", cascadeProtocol: PluginProtocolVersion(major: 2, minimumMinor: 0)),
            execution      : PluginExecution(entryPoint: "ClockPlugin"),
            sourceApp      : nil,
            requires       : [],
            features       : [
                PluginFeature(id: "time", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 3, rows: 1)]))),
                PluginFeature(id: "alarm", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 1), PluginWidgetSize(columns: 2, rows: 2)]))),
                PluginFeature(
                    id      : "mixer",
                    surfaces: PluginSurfaces(
                        widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 2, rows: 1)]),
                        detail: PluginPlainSurface()
                    )
                ),
            ],
            resources      : PluginResources(profile: .eventDriven)
        )
        rig.surfaces = PluginSurfaceRouter(
            host           : rig.host,
            manifests      : [manifest],
            placedByDefault: placedByDefault,
            submit         : { [unowned rig] in rig.submitted.append($0) },
            visibility     : { [unowned rig] isVisible, key in rig.visibility.append((isVisible, key)) }
        )
        return rig
    }

    private func publish(
        _ document  : PluginDocument,
        in publisher: inout PluginPublicationStore,
        for key     : PluginPublicationKey? = nil
    ) -> PluginPublicationChange {
        let key = key ?? widgetKey

        return publisher.apply(document, staleAfter: nil, for: key, at: Date()) ?? PluginPublicationChange(key: key, revision: 0, content: nil)
    }

    @Test
    func theFirstContentRegistersOneWidget() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])

        let widget = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        #expect(rig.host.registrations == 1)
        #expect(widget.store.root?.kind == .clock)
    }

    @Test
    func theWidgetTakesItsDeclaredSize() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])

        #expect(rig.host.widgets[widgetID]?.size == GridSpan(columns: 6, rows: 1))
    }

    @Test
    func theWidgetOffersEveryDeclaredSizeInTheManifestsOrder() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher, for: alarmKey)], rejected: [])

        let alarm = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/alarm")])
        #expect(alarm.sizes == [GridSpan(columns: 2, rows: 1), GridSpan(columns: 4, rows: 2)])
        #expect(alarm.size == GridSpan(columns: 2, rows: 1))
    }

    @Test
    func onlyAPluginPlacedByDefaultRegistersAWidgetPlacedByDefault() throws {
        let waiting   = try rig()
        let placed    = try rig(placedByDefault: [clock])
        var publisher = PluginPublicationStore()
        let content   = publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)

        waiting.surfaces.apply([content], rejected: [])
        placed.surfaces.apply([content], rejected: [])

        #expect(waiting.host.widgets[widgetID]?.isPlacedByDefault == false)
        #expect(placed.host.widgets[widgetID]?.isPlacedByDefault == true)
    }

    @Test
    func laterChangesUpdateTheSameWidget() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.text("One"))), in: &publisher)], rejected: [])

        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.text("Two"))), in: &publisher)], rejected: [])

        let widget = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        #expect(rig.host.registrations == 1)
        #expect(widget.store.root?.kind == .text("Two"))
    }

    @Test
    func aWithdrawalRemovesTheWidget() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])
        let withdrawn  = publisher.withdraw(widgetKey)
        let withdrawal = try #require(withdrawn)

        rig.surfaces.apply([withdrawal], rejected: [])

        #expect(rig.host.widgets.isEmpty)
    }

    @Test
    func activationAndSuspensionReportVisibility() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])
        let widget = try #require(rig.host.widgets[widgetID])

        widget.activate(in: WidgetContext(state: .open, requestContent: {}))
        widget.suspend()

        #expect(rig.visibility.map(\.0) == [true, false])
        #expect(rig.visibility.allSatisfy { $0.1 == widgetKey })
    }

    @Test
    func aRefusalRevertsItsControlAndNoOther() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let toggle    = try PluginDocument(root: PluginNode(.toggle(isOn: true, action: "flip"), id: "flip"))
        rig.surfaces.apply([publish(toggle, in: &publisher), publish(toggle, in: &publisher, for: alarmKey)], rejected: [])
        let time  = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        let alarm = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/alarm")] as? PluginWidget)
        let flip  = PluginNodeID(rawValue: "#flip:toggle")
        let timeToggle  = try #require(time.store.model(flip))
        let alarmToggle = try #require(alarm.store.model(flip))
        time.store.set(.bool(false), on: timeToggle)
        alarm.store.set(.bool(false), on: alarmToggle)

        rig.surfaces.apply([], rejected: [try #require(rig.submitted.first { $0.key == alarmKey })])

        #expect(timeToggle.optimistic == .bool(false))
        #expect(alarmToggle.optimistic == nil)
    }

    /// openedDetailRig routes the mixer's widget and detail publications, the way an engine
    /// delivers them, and returns the widget that opens the detail.
    private func openedDetailRig() throws -> (rig: Rig, widget: PluginWidget) {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let document  = try PluginDocument(root: PluginNode(.text("Mixer")))

        rig.surfaces.apply(
            [
                publish(document, in: &publisher, for: mixerKey),
                publish(document, in: &publisher, for: detailKey),
            ],
            rejected: []
        )
        let widget = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/mixer")] as? PluginWidget)
        return (rig, widget)
    }

    @Test
    func detailPublicationIsKeptButNotShown() throws {
        let (rig, _) = try openedDetailRig()

        #expect(rig.host.shownDetails.isEmpty)
        #expect(rig.host.registrations == 1)
    }

    @Test
    func openingTheWidgetsDetailShowsItAndReportsVisibility() throws {
        let (rig, widget) = try openedDetailRig()
        let open          = try #require(widget.openDetail)

        open()

        #expect(rig.host.shownDetails.count == 1)
        #expect(rig.host.shownDetails.first?.page.id == detailID)
        #expect(rig.host.shownDetails.first?.displayID == nil)
        #expect(rig.visibility.map(\.0) == [true])
        #expect(rig.visibility.map(\.1) == [detailKey])
    }

    @Test
    func dismissingTheDetailReportsItHidden() throws {
        let (rig, widget) = try openedDetailRig()
        widget.openDetail?()

        rig.host.shownDetails[0].onDismiss()

        #expect(rig.visibility.map(\.0) == [true, false])
        #expect(rig.visibility.map(\.1) == [detailKey, detailKey])
    }

    @Test
    func closingAndReopeningTheNotchOverTheDetailReportsItHiddenAndVisible() throws {
        let (rig, widget) = try openedDetailRig()
        widget.openDetail?()

        rig.host.shownDetails[0].onPresented(false)
        rig.host.shownDetails[0].onPresented(true)

        #expect(rig.visibility.map(\.0) == [true, false, true])
        #expect(rig.visibility.map(\.1) == [detailKey, detailKey, detailKey])
    }

    @Test
    func withdrawingAnOpenDetailDismissesIt() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let document  = try PluginDocument(root: PluginNode(.text("Mixer")))
        rig.surfaces.apply(
            [
                publish(document, in: &publisher, for: mixerKey),
                publish(document, in: &publisher, for: detailKey),
            ],
            rejected: []
        )
        let widget     = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/mixer")] as? PluginWidget)
        let withdrawn  = publisher.withdraw(detailKey)
        let withdrawal = try #require(withdrawn)
        widget.openDetail?()

        rig.surfaces.apply([withdrawal], rejected: [])

        #expect(rig.host.dismissedDetailIDs == [detailID])
    }

    @Test
    func withdrawingAClosedDetailDismissesNothing() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let document  = try PluginDocument(root: PluginNode(.text("Mixer")))
        rig.surfaces.apply([publish(document, in: &publisher, for: detailKey)], rejected: [])
        let withdrawn  = publisher.withdraw(detailKey)
        let withdrawal = try #require(withdrawn)

        rig.surfaces.apply([withdrawal], rejected: [])

        #expect(rig.host.dismissedDetailIDs.isEmpty)
    }

    @Test
    func theDetailsBackButtonDismissesItThroughTheHost() throws {
        let (rig, widget) = try openedDetailRig()
        widget.openDetail?()

        let detail = try #require(rig.host.shownDetails.first?.page as? PluginDetail)
        detail.back()

        #expect(rig.host.dismissedDetailIDs == [detailID])
    }

    @Test
    func theDetailReadsTheNotchObstructionFromItsContext() throws {
        let (rig, widget) = try openedDetailRig()
        widget.openDetail?()
        let detail  = try #require(rig.host.shownDetails.first?.page as? PluginDetail)
        let notch   = CGRect(x: 110, y: 0, width: 180, height: 28)
        let context = NotchContextualPageContext(
            availableSize         : CGSize(width: 400, height: 124),
            centerObstructionFrame: notch
        )

        #expect(detail.detailView(in: context).obstruction == notch)
        #expect(detail.contentHeight == 144)
    }

    @Test
    func theBackButtonSitsInTheLeftShoulderBesideTheNotch() {
        let covered = PluginDetailView.backButtonOrigin(obstruction: CGRect(x: 110, y: 0, width: 180, height: 32))
        let free    = PluginDetailView.backButtonOrigin(obstruction: .zero)

        #expect(covered == CGPoint(x: 4, y: 4))
        #expect(free == CGPoint(x: 4, y: 4))
        #expect(PluginDetailView.backButtonOrigin(obstruction: CGRect(x: 110, y: 0, width: 180, height: 40)).y == 8)
    }

    @Test
    func refusedDetailIsNeitherOpenNorVisible() throws {
        let (rig, widget) = try openedDetailRig()
        rig.host.refusesDetails = true

        widget.openDetail?()

        #expect(rig.host.shownDetails.isEmpty)
        #expect(rig.visibility.isEmpty)
    }

    @Test
    func widgetWithoutDetailHasNoOpenAction() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher)], rejected: [])

        let widget = try #require(rig.host.widgets[widgetID] as? PluginWidget)

        #expect(widget.openDetail == nil)
    }

    @Test
    func openingBeforeTheDetailHasContentShowsNothing() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        rig.surfaces.apply([publish(try PluginDocument(root: PluginNode(.clock)), in: &publisher, for: mixerKey)], rejected: [])
        let widget = try #require(rig.host.widgets[WidgetIdentifier("plugin:com.cascade.clock/mixer")] as? PluginWidget)

        widget.openDetail?()

        #expect(rig.host.shownDetails.isEmpty)
        #expect(rig.visibility.isEmpty)
    }

    @Test
    func activitiesWaitForTheirPlan() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let key       = PluginPublicationKey(plugin: clock, feature: "time", surface: .activity)
        let applied   = publisher.apply(try PluginDocument(root: PluginNode(.clock)), staleAfter: nil, for: key, at: Date())
        let change    = try #require(applied)

        rig.surfaces.apply([change], rejected: [])

        #expect(rig.host.widgets.isEmpty)
    }
}
