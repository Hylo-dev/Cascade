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

    /// Rig is a router over a recording host, with what they submitted and reported.
    @MainActor
    final class Rig {

        let host      = RecordingWidgetHost()
        var submitted : [PluginActionRequest] = []
        var visibility: [(Bool, PluginPublicationKey)] = []
        var surfaces  : PluginSurfaceRouter!
    }

    private func rig() throws -> Rig {
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
                PluginFeature(id: "alarm", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 1)]))),
            ],
            resources      : PluginResources(profile: .eventDriven)
        )
        rig.surfaces = PluginSurfaceRouter(
            widgets   : rig.host,
            manifests : [manifest],
            submit    : { [unowned rig] in rig.submitted.append($0) },
            visibility: { [unowned rig] isVisible, key in rig.visibility.append((isVisible, key)) }
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

    @Test
    func activitiesAndNoticesWaitForTheirPlans() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let key       = PluginPublicationKey(plugin: clock, feature: "time", surface: .notice)
        let applied   = publisher.apply(try PluginDocument(root: PluginNode(.clock)), staleAfter: nil, for: key, at: Date())
        let change    = try #require(applied)

        rig.surfaces.apply([change], rejected: [])

        #expect(rig.host.widgets.isEmpty)
    }
}
