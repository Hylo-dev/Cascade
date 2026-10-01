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

    /// Rig is a router over a recording host, with what they submitted and reported.
    @MainActor
    final class Rig {

        let host      = RecordingWidgetHost()
        var submitted : [PluginActionRequest] = []
        var visibility: [Bool] = []
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
                PluginFeature(id: "time", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 2, rows: 1)]))),
            ],
            resources      : PluginResources(profile: .eventDriven)
        )
        rig.surfaces = PluginSurfaceRouter(
            widgets   : rig.host,
            manifests : [manifest],
            submit    : { [unowned rig] in rig.submitted.append($0) },
            visibility: { [unowned rig] isVisible, _ in rig.visibility.append(isVisible) }
        )
        return rig
    }

    private func publish(
        _ document  : PluginDocument,
        in publisher: inout PluginPublicationStore
    ) -> PluginPublicationChange {
        publisher.apply(document, staleAfter: nil, for: widgetKey, at: Date()) ?? PluginPublicationChange(key: widgetKey, revision: 0, content: nil)
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

        #expect(rig.host.widgets[widgetID]?.size == GridSpan(columns: 4, rows: 1))
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

        #expect(rig.visibility == [true, false])
    }

    @Test
    func aRefusalRevertsItsControl() throws {
        let rig       = try rig()
        var publisher = PluginPublicationStore()
        let toggle    = try PluginDocument(root: PluginNode(.toggle(isOn: true, action: "flip"), id: "flip"))
        rig.surfaces.apply([publish(toggle, in: &publisher)], rejected: [])
        let widget = try #require(rig.host.widgets[widgetID] as? PluginWidget)
        let model  = try #require(widget.store.model(PluginNodeID(rawValue: "#flip:toggle")))
        widget.store.set(.bool(false), on: model)

        rig.surfaces.apply([], rejected: [try #require(rig.submitted.first)])

        #expect(model.optimistic == nil)
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
