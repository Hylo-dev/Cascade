//
//  NotchDisplayCoordinatorTests.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct NotchDisplayCoordinatorTests {

    @Test
    func preferredPersistentContextualPageOpensAndStaysSelected() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(
            id                       : "shelf",
            contentRevision          : 1,
            keepsExpandedPresentation: true
        )
        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)

        fixture.coordinator.start()

        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)

        fixture.coordinator.showOrdinaryPage(on: 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
    }

    @Test
    func persistentContextualPageOpensWhenItBecomesOccupied() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        #expect(fixture.coordinator.expandedDisplayID == nil)

        shelf.keepsExpandedPresentation = true
        shelf.contentRevision           = 2
        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)

        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
    }

    @Test
    func persistentTransitionOwnsAnAlreadyExpandedSurfaceUntilEmpty() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .drag,
            generation: 1
        )

        shelf.keepsExpandedPresentation = true
        shelf.contentRevision           = 2
        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)

        shelf.keepsExpandedPresentation = false
        shelf.contentRevision           = 3
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)

        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)

        let generation = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: generation)
        #expect(fixture.coordinator.expandedDisplayID == nil)
    }

    @Test
    func preferredOrdinaryContextualPageDoesNotOpenAClosedSurface() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        fixture.coordinator.setContextualPage(
            CoordinatorContextualPage(id: "shelf", contentRevision: 1),
            prefersDefault: true
        )

        fixture.coordinator.start()

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[10]?.presentations.last?.isExpanded == false)
    }

    @Test
    func emptyingPersistentContextualPageReturnsToClosedOrdinaryState() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(
            id                       : "shelf",
            contentRevision          : 1,
            keepsExpandedPresentation: true
        )
        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)
        fixture.coordinator.start()

        shelf.keepsExpandedPresentation = false
        shelf.contentRevision           = 2
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)

        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)

        let generation = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: generation)
        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[10]?.presentations.last?.isExpanded == false)
    }

    @Test
    func persistentContextualPageReopensAfterUnlock() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        fixture.coordinator.setContextualPage(
            CoordinatorContextualPage(
                id                       : "shelf",
                contentRevision          : 1,
                keepsExpandedPresentation: true
            ),
            prefersDefault: true
        )
        fixture.coordinator.start()

        fixture.monitor.sendLock()
        #expect(fixture.coordinator.expandedDisplayID == nil)

        fixture.monitor.sendUnlock()
        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
    }

    @Test
    func occupiedContextualPageIsDefaultOnlyForANewOpening() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let music   = CoordinatorActivityFixture(id: "music")
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.activityHost.present(music)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)
        fixture.coordinator.start()

        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)

        fixture.coordinator.showOrdinaryPage(on: 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)
        #expect(fixture.surfaces[10]?.presentations.last?.expanded === music)

        shelf.contentRevision = 2
        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)
        #expect(fixture.surfaces[10]?.presentations.last?.expanded === music)

        fixture.surfaces[10]?.requestCollapse()
        let generation = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: generation)
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 2
        )
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
    }

    @Test
    func emptyContextualPageRequiresExplicitSelectionAndReturnsToOrdinaryWhenEmptied() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )

        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)
        #expect(fixture.surfaces[10]?.presentations.last?.showsWidgets == true)

        fixture.coordinator.showContextualPage(on: 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)

        fixture.coordinator.setContextualPage(shelf, prefersDefault: true)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)
        #expect(fixture.surfaces[10]?.presentations.last?.showsWidgets == true)
    }

    @Test
    func explicitContextualSelectionSurvivesAnOwnershipHandoff() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )

        fixture.coordinator.showContextualPage(on: 20)
        let generation = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: generation)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[20]?.presentations.last?.contextualPageIsSelected == true)
    }

    @Test
    func dragHoverPreviewRestoresThePreviouslySelectedPageUnlessDropSucceeds() {
        let fixture     = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf       = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        let url         = URL(fileURLWithPath: "/tmp/report.txt")
        var hovered    : [[URL]?] = []
        var acceptsDrop = false
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.configureFileDrop(
            onHover      : { hovered.append($0) },
            onDrop       : { _ in acceptsDrop },
            onUnsupported: {}
        )
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )

        fixture.surfaces[10]?.sendFileDragHover([url])
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)

        fixture.surfaces[10]?.sendFileDragHover(nil)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)

        fixture.surfaces[10]?.sendFileDragHover([url])
        #expect(fixture.surfaces[10]?.sendFileDrop([url]) == false)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)

        fixture.surfaces[10]?.sendFileDragHover([url])
        acceptsDrop = true
        #expect(fixture.surfaces[10]?.sendFileDrop([url]) == true)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
        #expect(hovered == [[url], nil, [url], nil, [url], nil])
    }

    @Test
    func validatedDropBeforePreviewExpansionStillReachesTheShelf() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        let url     = URL(fileURLWithPath: "/tmp/report.txt")
        var dropped: [[URL]] = []
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.configureFileDrop(
            onHover      : { _ in },
            onDrop       : {
                dropped.append($0)
                return true
            },
            onUnsupported: {}
        )
        fixture.coordinator.start()

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[10]?.sendFileDrop([url]) == true)
        #expect(dropped == [[url]])
        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
    }

    @Test
    func recognizedFileDragRoutesToPointedDisplayAndLockClearsIt() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.setContextualPage(
            CoordinatorContextualPage(id: "shelf", contentRevision: 1),
            prefersDefault: false
        )
        fixture.coordinator.configureFileDrop(
            onHover      : { _ in },
            onDrop       : { _ in true },
            onUnsupported: {}
        )
        fixture.coordinator.start()
        let point = CGPoint(x: 1_050, y: 50)

        fixture.monitor.sendPointer(point)
        #expect(fixture.surfaces[20]?.fileDragRecognitionUpdates.isEmpty == true)

        fixture.monitor.sendRecognizedFileDrag(
            active               : true,
            point                : point,
            hasValidatedOfferHint: true
        )
        #expect(fixture.surfaces[10]?.fileDragRecognitionUpdates.isEmpty == true)
        #expect(fixture.surfaces[20]?.fileDragRecognitionUpdates == [true])
        #expect(fixture.surfaces[20]?.fileDragOfferHintUpdates == [true])

        fixture.monitor.sendLock()
        #expect(fixture.surfaces[20]?.fileDragRecognitionUpdates == [true, false])
    }

    @Test
    func fileDropDestinationRequiresBothAContextualPageAndDropHandler() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        fixture.coordinator.start()
        #expect(fixture.surfaces[10]?.fileDropEnabledUpdates.last == false)

        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        #expect(fixture.surfaces[10]?.fileDropEnabledUpdates.last == false)

        fixture.coordinator.configureFileDrop(
            onHover      : { _ in },
            onDrop       : { _ in true },
            onUnsupported: {}
        )
        #expect(fixture.surfaces[10]?.fileDropEnabledUpdates.last == true)

        fixture.coordinator.setContextualPage(nil, prefersDefault: false)
        #expect(fixture.surfaces[10]?.fileDropEnabledUpdates.last == false)
    }

    @Test
    func mouseUpDoesNotRestorePreviewBeforeDestinationDropIsDelivered() async {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        let url     = URL(fileURLWithPath: "/tmp/report.txt")
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.configureFileDrop(
            onHover      : { _ in },
            onDrop       : { _ in true },
            onUnsupported: {}
        )
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.monitor.sendRecognizedFileDrag(active: true, point: CGPoint(x: 50, y: 90))
        fixture.surfaces[10]?.sendFileDragHover([url])

        fixture.monitor.sendRecognizedFileDrag(active: false, point: CGPoint(x: 50, y: 90))
        #expect(fixture.surfaces[10]?.fileDragGestureEndCount == 1)

        for _ in 0..<4 { await Task.yield() }
        #expect(fixture.surfaces[10]?.sendFileDrop([url]) == true)

        await Task.yield()

        #expect(fixture.surfaces[10]?.presentations.last?.contextualPage === shelf)
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)
        #expect(fixture.surfaces[10]?.fileDragRecognitionUpdates == [true, false])
    }

    @Test
    func nativeFileDragExitAfterMouseUpRestoresThePreviousPageAndIntake() async {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        let url     = URL(fileURLWithPath: "/tmp/report.txt")
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.configureFileDrop(
            onHover      : { _ in },
            onDrop       : { _ in true },
            onUnsupported: {}
        )
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.monitor.sendRecognizedFileDrag(active: true, point: CGPoint(x: 50, y: 90))
        fixture.surfaces[10]?.sendFileDragHover([url])
        fixture.monitor.sendRecognizedFileDrag(active: false, point: CGPoint(x: 50, y: 90))
        for _ in 0..<4 { await Task.yield() }

        fixture.surfaces[10]?.sendFileDragHover(nil)
        await Task.yield()

        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == false)
        #expect(fixture.surfaces[10]?.fileDragRecognitionUpdates == [true, false])
    }

    @Test
    func handoffWaitsForTheOldSurfaceToReachCompactGeometry() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()

        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.presentations.last?.isExpanded == true)

        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.closeRequests.count == 1)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == false)

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == true)
        #expect(fixture.surfaces.count == 2)
        #expect(fixture.surfaces.values.allSatisfy { $0.isStarted })
    }

    @Test
    func rapidHandoffUsesTheNewestStillValidRequest() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20, 30])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .hover,
            generation: 8
        )
        fixture.surfaces[30]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 3
        )

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 30)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == false)
        #expect(fixture.surfaces[30]?.presentations.last?.isExpanded == true)
    }

    @Test
    func cancelledPendingHoverLeavesEverySurfaceCompact() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .hover,
            generation: 9
        )
        fixture.surfaces[20]?.cancelExpansion(generation: 9)

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces.values.allSatisfy { $0.presentations.last?.isExpanded == false })
    }

    @Test
    func cancelledNewestHoverRestoresTheOlderExplicitCandidate() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20, 30])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[30]?.requestExpansion(
            activityID: nil,
            trigger   : .hover,
            generation: 1
        )

        fixture.surfaces[30]?.cancelExpansion(generation: 1)
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == true)
        #expect(fixture.surfaces[30]?.presentations.last?.isExpanded == false)
    }

    @Test
    func disconnectingTheOwnerDuringHandoffDoesNotOpenThePendingSurface() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 2
        )

        fixture.inventory.entries = [fixture.entry(displayID: 20)]
        fixture.inventory.sendChange()

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[10]?.isStopped == true)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == false)
    }

    @Test
    func disconnectingAContextualPreviewOwnerClearsItsSelection() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let shelf   = CoordinatorContextualPage(id: "shelf", contentRevision: 1)
        let url     = URL(fileURLWithPath: "/tmp/report.txt")
        fixture.coordinator.setContextualPage(shelf, prefersDefault: false)
        fixture.coordinator.configureFileDrop(
            onHover      : { _ in },
            onDrop       : { _ in true },
            onUnsupported: {}
        )
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[10]?.sendFileDragHover([url])
        #expect(fixture.surfaces[10]?.presentations.last?.contextualPageIsSelected == true)

        fixture.inventory.entries = [fixture.entry(displayID: 20)]
        fixture.inventory.sendChange()

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.contextualPageIsSelected == false)
    }

    @Test
    func routingUpdatesPresentationsWithoutRecreatingWindows() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20], missingIdentity: 20)
        fixture.activityHost.present(CoordinatorActivityFixture(id: "music"))
        fixture.coordinator.start()

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(activityMode: .allDisplays))
        #expect(fixture.surfaces[10]?.presentations.last?.primary?.id == "music")
        #expect(fixture.surfaces[20]?.presentations.last?.primary?.id == "music")

        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(activityMode: .focusedDisplay))
        #expect(fixture.surfaces[10]?.presentations.last?.primary == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.primary?.id == "music")

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .fixedDisplay(DisplayIdentity(rawValue: "display-10"))
        ))
        #expect(fixture.surfaces[10]?.presentations.last?.primary?.id == "music")
        #expect(fixture.surfaces[20]?.presentations.last?.primary == nil)
        #expect(fixture.surfaceCreationCount == 2)
    }

    @Test
    func activationPrecedesEverySurfaceFactory() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)

        fixture.coordinator.start()

        #expect(activity.activations == 1)
        #expect(activity.factoryCount == 2)
        #expect(!activity.factoryRanBeforeActivation)
    }

    /// threeDisplayCopiesShareOneLifecycleAndExpiry verifies the shared host with
    /// local fake roots; advancing the clock does not measure native timer activity.
    @Test
    func threeDisplayCopiesShareOneLifecycleAndExpiry() {
        var now     = Date()
        let fixture = DisplayCoordinatorFixture(
            displayIDs: [10, 20, 30],
            now       : { now }
        )
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)
        fixture.coordinator.start()

        #expect(fixture.surfaceCreationCount == 3)
        #expect(activity.factoryCount == 3)
        #expect(activity.activations == 1)
        #expect(!activity.factoryRanBeforeActivation)

        for surface in fixture.surfaces.values {
            #expect(surface.presentations.last?.primary === activity)
        }

        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(activityMode: .focusedDisplay))
        fixture.focus.send(frame: fixture.entry(displayID: 30).snapshot.frame)
        #expect(fixture.surfaces[30]?.presentations.last?.primary === activity)
        #expect(fixture.surfaces[10]?.presentations.last?.primary == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.primary == nil)

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(activityMode: .allDisplays))
        for surface in fixture.surfaces.values {
            #expect(surface.presentations.last?.primary === activity)
        }
        #expect(fixture.surfaceCreationCount == 3)
        #expect(activity.activations == 1)
        #expect(activity.suspensions == 0)

        now = now.addingTimeInterval(61)
        fixture.activityHost.expireNotices()
        for surface in fixture.surfaces.values {
            #expect(surface.presentations.last?.primary == nil)
            #expect(surface.presentations.last?.secondary == nil)
            #expect(surface.presentations.last?.expanded == nil)
        }
        #expect(activity.suspensions == 1)
        #expect(activity.activeCount == 0)

        let presentationCounts = fixture.surfaces.mapValues { $0.presentations.count }
        fixture.activityHost.expireNotices()
        #expect(fixture.surfaces.mapValues { $0.presentations.count } == presentationCounts)
        #expect(activity.activations == 1)
        #expect(activity.suspensions == 1)
        #expect(fixture.surfaceCreationCount == 3)

        fixture.coordinator.stop()
    }

    @Test
    func queuedExplicitActivityCannotBypassNewFixedRoutingAtGrant() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.activityHost.present(CoordinatorActivityFixture(id: "music"))
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: "music",
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: "music",
            trigger   : .click,
            generation: 2
        )

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .fixedDisplay(DisplayIdentity(rawValue: "display-10"))
        ))
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.expanded == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.showsWidgets == true)
    }

    @Test
    func ownerCollapseRequestDoesNotDiscardAnotherDisplaysPendingGrant() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.coordinator.setInteractionHold(
            .popover,
            on    : 10,
            active: true
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 2
        )
        #expect(fixture.surfaces[10]?.closeRequests.isEmpty == true)

        fixture.coordinator.setInteractionHold(
            .popover,
            on    : 10,
            active: false
        )
        fixture.surfaces[10]?.requestCollapse()
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == true)
    }

    @Test
    func focusedCopyMovesWithoutSuspendingTheSharedActivity() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)
        fixture.coordinator.start()
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .focusedDisplay
        ))

        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)

        #expect(fixture.surfaces[10]?.presentations.last?.primary == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.primary === activity)
        #expect(activity.activations == 1)
        #expect(activity.suspensions == 0)
    }

    @Test
    func synchronousInvalidationDuringActivationBuildsNoSurfaceRoots() {
        let fixture       = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let first         = CoordinatorActivityFixture(id: "first", sourceID: "first-source")
        let second        = CoordinatorActivityFixture(id: "second", sourceID: "second-source")
        var invalidated   = false
        let invalidateAll = {
            guard !invalidated else { return }

            invalidated = true
            fixture.activityHost.dismissActivities(from: "first-source")
            fixture.activityHost.dismissActivities(from: "second-source")
        }
        first.onActivate  = invalidateAll
        second.onActivate = invalidateAll
        fixture.activityHost.present(first)
        fixture.activityHost.present(second)

        fixture.coordinator.start()

        #expect(first.factoryCount == 0)
        #expect(second.factoryCount == 0)
        #expect(first.activeCount == 0)
        #expect(second.activeCount == 0)
    }

    @Test
    func visibleSettingsDoNotBlockAnotherDisplayFromExpanding() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.setSettingsFocused(true)
        #expect(fixture.coordinator.expandedDisplayID == 10)

        fixture.coordinator.setSettingsFocused(false)

        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.coordinator.settingsAnchorDisplayID == 10)
        #expect(fixture.surfaces[10]?.settingsFocusUpdates == [true, false])
    }

    @Test
    func focusedSettingsKeepTheirOwnerUntilFocusEnds() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.setSettingsFocused(true)

        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.surfaces[20]?.closeRequests.isEmpty == true)
        #expect(fixture.coordinator.expandedDisplayID == 20)

        fixture.coordinator.setSettingsFocused(false)
        let closeGeneration = try #require(fixture.surfaces[20]?.closeRequests.last)
        fixture.surfaces[20]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 10)
    }

    @Test
    func visibleSettingsKeepTheirInvocationAnchorAfterAnotherDisplayExpands() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.setSettingsFocused(true)
        fixture.coordinator.setSettingsFocused(false)
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.coordinator.settingsAnchorDisplayID == 10)
        #expect(fixture.coordinator.restingFrame(on: 10) == fixture.surfaces[10]?.restingFrame)
    }

    @Test
    func explicitSettingsRequestMovesTheAnchorToItsInvokingDisplay() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.setSettingsFocused(false)
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[20]?.closeRequests.last)
        fixture.surfaces[20]?.finishCollapse(generation: closeGeneration)

        fixture.surfaces[10]?.onSettingsRequested?()

        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.coordinator.auxiliaryDisplayID == 10)
        #expect(fixture.coordinator.restingFrame == fixture.surfaces[10]?.restingFrame)
    }

    @Test
    func globalSettingsInvocationReanchorsFromAStaleVisibleWindowToTheCurrentOwner() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.setSettingsFocused(false)
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[20]?.closeRequests.last)
        fixture.surfaces[20]?.finishCollapse(generation: closeGeneration)

        fixture.coordinator.setSettingsPresented(true, reanchorToCurrentOwner: true)
        fixture.coordinator.setSettingsFocused(true)

        #expect(fixture.coordinator.settingsAnchorDisplayID == 10)
        #expect(fixture.surfaces[10]?.settingsFocusUpdates.last == true)
    }

    @Test
    func contextualExternalSurfaceWaitsForAnotherOwnersActualCollapse() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        var readyCount = 0

        fixture.coordinator.reserveExternalSurface(on: 20) { readyCount += 1 }

        #expect(readyCount == 0)
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates.isEmpty == true)

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        #expect(readyCount == 1)
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates == [true])
        #expect(fixture.coordinator.expandedDisplayID == nil)
    }

    @Test
    func externalReservationWaitsForAnotherOwnersInteractionToEnd() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.coordinator.setInteractionHold(
            .popover,
            on    : 10,
            active: true
        )
        var readyCount = 0

        fixture.coordinator.reserveExternalSurface(on: 20) { readyCount += 1 }

        #expect(fixture.surfaces[10]?.closeRequests.isEmpty == true)
        #expect(readyCount == 0)

        fixture.coordinator.setInteractionHold(
            .popover,
            on    : 10,
            active: false
        )
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        #expect(readyCount == 1)
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates == [true])
    }

    @Test
    func globalExternalSurfaceUsesTheCurrentOwnerInsteadOfAStaleSettingsAnchor() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.setSettingsFocused(false)
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[20]?.closeRequests.last)
        fixture.surfaces[20]?.finishCollapse(generation: closeGeneration)

        fixture.coordinator.setExternalSurfacePresented(true)

        #expect(fixture.surfaces[10]?.externalSurfaceUpdates == [true])
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates.isEmpty == true)
    }

    @Test
    func screenLockReleasesTheOriginalExternalSurfaceAndCannotReplayItAfterUnlock() {
        let fixture                        = DisplayCoordinatorFixture(displayIDs: [10, 20])
        var screenLockCount                = 0
        fixture.coordinator.onScreenLocked = { screenLockCount += 1 }
        fixture.coordinator.start()
        fixture.coordinator.reserveExternalSurface(on: 20) {}
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates == [true])

        fixture.monitor.sendLock()
        fixture.monitor.sendUnlock()

        #expect(screenLockCount == 1)
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates == [true, false])

        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates == [true, false])
    }

    @Test
    func screenLockCancelsAPendingCrossDisplayExternalReservation() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        var readyCount = 0
        fixture.coordinator.reserveExternalSurface(on: 20) { readyCount += 1 }
        let staleGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)

        fixture.monitor.sendLock()
        fixture.monitor.sendUnlock()
        fixture.surfaces[10]?.finishCollapse(generation: staleGeneration)

        #expect(readyCount == 0)
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates.isEmpty == true)

        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 2
        )
        #expect(fixture.coordinator.expandedDisplayID == 10)
    }

    @Test
    func screenLockInvalidatesQueuedExpansionBeforeApplicationCleanup() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.coordinator.reserveExternalSurface(on: 10) {}
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.coordinator.onScreenLocked = {
            fixture.coordinator.releaseExternalSurface()
        }

        fixture.monitor.sendLock()

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[20]?.presentations.contains(where: \.isExpanded) == false)
    }

    @Test
    func spotlightPreviewFromSettingsUsesTheVisibleWindowAnchorAfterStyleCollapse() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)
        fixture.coordinator.setSettingsPresented(true)
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .allDisplays,
            styles      : [DisplayIdentity(rawValue: "display-20"): .dynamicIsland]
        ))
        let closeGeneration = try #require(fixture.surfaces[20]?.closeRequests.last)
        fixture.surfaces[20]?.finishCollapse(generation: closeGeneration)
        fixture.focus.send(frame: fixture.entry(displayID: 10).snapshot.frame)

        fixture.coordinator.reserveExternalSurface(on: 20) {}

        #expect(fixture.surfaces[20]?.externalSurfaceUpdates == [true])
        #expect(fixture.surfaces[10]?.externalSurfaceUpdates.isEmpty == true)
    }

    @Test
    func styleChangeCollapsesOwnerBeforeApplyingNewGeometry() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [20])
        fixture.coordinator.start()
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .allDisplays,
            styles      : [DisplayIdentity(rawValue: "display-20"): .dynamicIsland]
        ))

        #expect(fixture.surfaces[20]?.presentations.last?.style == .notch)

        let closeGeneration = try #require(fixture.surfaces[20]?.closeRequests.last)
        fixture.surfaces[20]?.finishCollapse(generation: closeGeneration)
        #expect(fixture.surfaces[20]?.presentations.last?.style == .dynamicIsland)
    }

    @Test
    func runtimeOnlyDisplayStyleLivesUntilThatDisplayDisconnects() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [20], missingIdentity: 20)
        fixture.coordinator.start()
        fixture.coordinator.setTransientDisplayStyle(.dynamicIsland, for: 20)
        #expect(fixture.surfaces[20]?.presentations.last?.style == .dynamicIsland)

        fixture.inventory.entries = []
        fixture.inventory.sendChange()
        fixture.inventory.entries = [fixture.entry(displayID: 20)]
        fixture.inventory.sendChange()
        #expect(fixture.surfaces[20]?.presentations.last?.style == .notch)
    }

    @Test
    func pointerMovesWithinTheFocusedDisplayDoNotReconcilePresentations() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        let first  = fixture.entry(displayID: 10).snapshot.frame
        let second = fixture.entry(displayID: 20).snapshot.frame
        func appliedCount() -> Int { fixture.surfaces.values.map(\.presentations.count).reduce(0, +) }
        fixture.monitor.sendPointer(CGPoint(x: first.midX, y: first.midY))
        let settled = appliedCount()

        for step in 1...50 {
            fixture.monitor.sendPointer(CGPoint(x: first.minX + CGFloat(step), y: first.midY))
        }
        #expect(appliedCount() == settled)

        fixture.monitor.sendPointer(CGPoint(x: second.midX, y: second.midY))
        #expect(appliedCount() > settled)
    }

    @Test
    func displaySleepSuspendsActivitiesAndWakeNeverRevealsALockedScreen() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)
        fixture.coordinator.start()

        fixture.monitor.sendScreensAsleep(true)
        #expect(fixture.surfaces.values.allSatisfy { $0.visibilityUpdates.last == false })
        #expect(activity.activeCount == 0)

        fixture.monitor.sendLock()
        fixture.monitor.sendScreensAsleep(false)
        #expect(fixture.surfaces.values.allSatisfy { $0.visibilityUpdates.last == false })
        #expect(activity.activeCount == 0)

        fixture.monitor.sendUnlock()
        #expect(fixture.surfaces.values.allSatisfy { $0.visibilityUpdates.last == true })
        #expect(activity.activeCount == 1)
    }

    @Test
    func lockUnlockAndStopUseOneSharedLifecycle() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)
        fixture.coordinator.start()

        fixture.monitor.sendLock()
        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces.values.allSatisfy { $0.visibilityUpdates.last == false })
        #expect(activity.activeCount == 0)

        fixture.monitor.sendUnlock()
        #expect(fixture.surfaces.values.allSatisfy { $0.visibilityUpdates.last == true })
        #expect(activity.activeCount == 1)

        fixture.coordinator.stop()
        fixture.coordinator.stop()
        #expect(fixture.surfaces.values.allSatisfy { $0.stopCount == 1 })
        #expect(fixture.inventory.stopCount == 1)
        #expect(fixture.focus.stopCount == 1)
        #expect(fixture.monitor.stopCount == 1)
        #expect(activity.activeCount == 0)
    }

    @Test
    func mountedReplacementStaysActiveUntilTheSurfaceReleasesItsOutgoingRoot() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        let old     = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(old)
        fixture.coordinator.start()
        fixture.surfaces[10]?.retainsOutgoingRootsOnReplacement = true
        #expect(fixture.surfaces[10]?.retainedActivityRoots.first === old)

        let replacement                            = CoordinatorActivityFixture(id: "music")
        var bothWereActiveBeforeReplacementFactory = false
        replacement.onCompactLeadingFactory        = {
            bothWereActiveBeforeReplacementFactory = old.activeCount == 1
                && replacement.activeCount == 1
        }
        fixture.activityHost.present(replacement)

        #expect(bothWereActiveBeforeReplacementFactory)
        #expect(old.activeCount == 1)
        #expect(replacement.activeCount == 1)
        #expect(fixture.surfaces[10]?.retainedActivityRoots.contains { $0 === old } == true)

        fixture.surfaces[10]?.releaseOutgoingRoots()
        #expect(old.activeCount == 0)
        #expect(old.suspensions == 1)
        #expect(replacement.activeCount == 1)
    }

    @Test
    func expandedOwnerDoesNotInventASecondaryRoot() {
        let fixture   = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let primary   = CoordinatorActivityFixture(id: "primary", sourceID: "music")
        let secondary = CoordinatorActivityFixture(id: "secondary", sourceID: "timer")
        fixture.activityHost.present(primary)
        fixture.activityHost.present(secondary)
        fixture.coordinator.start()

        fixture.surfaces[10]?.requestExpansion(
            activityID: primary.id,
            trigger   : .click,
            generation: 1
        )

        let owner       = fixture.surfaces[10]?.presentations.last
        let compactCopy = fixture.surfaces[20]?.presentations.last
        #expect(owner?.visibleActivityRoots.count == 1)
        #expect(owner?.expanded === primary)

        let compactIdentities = Set(compactCopy?.visibleActivityRoots.map(ObjectIdentifier.init) ?? [])
        #expect(compactIdentities == [ObjectIdentifier(primary), ObjectIdentifier(secondary)])
        #expect(secondary.activeCount == 1)
    }

    @Test
    func widgetHandoffRevokesOldOwnerBeforeOpeningTheNewOne() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let widget  = CoordinatorWidgetFixture()
        fixture.coordinator.register(widget)
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(widget.activations == 1)
        #expect(widget.suspensions == 0)

        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 2
        )
        #expect(widget.activations == 1)

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(widget.activations == 2)
        #expect(widget.suspensions == 1)
        #expect(fixture.surfaces[10]?.presentations.suffix(2).first?.showsWidgets == false)
        #expect(fixture.surfaces[20]?.presentations.last?.showsWidgets == true)
    }

    @Test
    func staleCloseCompletionCannotGrantThePendingDisplay() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)

        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration &+ 1)
        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == false)

        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        #expect(fixture.coordinator.expandedDisplayID == 20)
    }

    @Test
    func disconnectingPendingDisplayLeavesTheOwnerToFinishCompact() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)

        fixture.inventory.entries = [fixture.entry(displayID: 10)]
        fixture.inventory.sendChange()
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[10]?.presentations.last?.isExpanded == false)
        #expect(fixture.surfaces[20]?.isStopped == true)
    }

    @Test
    func pointerExitAndMouseUpReachOnlyRelevantSurfaces() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.monitor.sendPointer(CGPoint(x: 50, y: 50))
        fixture.monitor.sendPointer(CGPoint(x: 1_050, y: 50))
        #expect(fixture.surfaces[10]?.pointerUpdates.count == 2)
        #expect(fixture.surfaces[20]?.pointerUpdates.count == 1)

        fixture.surfaces[10]?.setDragOwner(true)
        fixture.monitor.sendButton(isPressed: false)

        #expect(fixture.surfaces[10]?.buttonUpdates == [false])
        #expect(fixture.surfaces[20]?.buttonUpdates.isEmpty == true)
    }

    @Test
    func explicitPreferenceChangeClosesAnExcludedOwner() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.activityHost.present(CoordinatorActivityFixture(id: "music"))
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: "music",
            trigger   : .click,
            generation: 1
        )

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .fixedDisplay(DisplayIdentity(rawValue: "display-20"))
        ))

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        #expect(fixture.coordinator.expandedDisplayID == 10)

        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces.values.allSatisfy { $0.presentations.last?.isExpanded == false })
    }

    @Test
    func focusMovementKeepsManualOwnerWhileCompactCopyMoves() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)
        fixture.coordinator.start()
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .focusedDisplay
        ))
        fixture.surfaces[10]?.requestExpansion(
            activityID: "music",
            trigger   : .click,
            generation: 1
        )

        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)

        #expect(fixture.coordinator.expandedDisplayID == 10)
        #expect(fixture.surfaces[10]?.closeRequests.isEmpty == true)
        #expect(fixture.surfaces[10]?.presentations.last?.expanded === activity)
        #expect(fixture.surfaces[20]?.presentations.last?.primary === activity)
        #expect(activity.activations == 1)
        #expect(activity.suspensions == 0)
    }

    @Test
    func excludedDisplayOpensWidgetsInsteadOfGlobalFallbackContent() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let fallback = CoordinatorActivityFixture(id: "fallback")
        fixture.activityHost.setExpandedFallback(fallback)
        fixture.coordinator.start()
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .fixedDisplay(DisplayIdentity(rawValue: "display-10"))
        ))

        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )

        #expect(fixture.surfaces[20]?.presentations.last?.showsWidgets == true)
        #expect(fixture.surfaces[20]?.presentations.last?.expanded == nil)
        #expect(fallback.activations == 0)
        #expect(fallback.factoryCount == 0)
    }

    @Test
    func presentationPreferencesApplyToPanelsCreatedAfterHotplug() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        fixture.coordinator.setHapticsEnabled(false)
        fixture.coordinator.setBorderAppearance(.connected)
        fixture.coordinator.setSensitiveContentVisible(true)
        fixture.coordinator.start()

        #expect(fixture.surfaces[10]?.hapticsUpdates.last == false)
        #expect(fixture.surfaces[10]?.borderUpdates.last == .connected)
        #expect(fixture.surfaces[10]?.sensitiveContentUpdates.last == true)

        fixture.inventory.entries.append(fixture.entry(displayID: 20))
        fixture.inventory.sendChange()
        #expect(fixture.surfaces[20]?.hapticsUpdates.last == false)
        #expect(fixture.surfaces[20]?.borderUpdates.last == .connected)
        #expect(fixture.surfaces[20]?.sensitiveContentUpdates.last == true)

        fixture.coordinator.setHapticsEnabled(true)
        fixture.coordinator.setBorderAppearance(.charging)
        fixture.coordinator.setSensitiveContentVisible(false)
        #expect(fixture.surfaces.values.allSatisfy { $0.hapticsUpdates.last == true })
        #expect(fixture.surfaces.values.allSatisfy { $0.borderUpdates.last == .charging })
        #expect(fixture.surfaces.values.allSatisfy { $0.sensitiveContentUpdates.last == false })
    }

    @Test
    func hardwareDisplayAlwaysUsesItsPhysicalNotchStyle() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10])
        fixture.coordinator.start()

        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .allDisplays,
            styles      : [DisplayIdentity(rawValue: "display-10"): .dynamicIsland]
        ))

        #expect(fixture.coordinator.displayDescriptors.first?.style == .notch)
        #expect(fixture.surfaces[10]?.presentations.last?.style == .notch)
    }

    @Test
    func spotlightDismissalReturnsToItsInvocationDisplayAfterFocusMoves() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.coordinator.setExternalSurfacePresented(true)
        fixture.surfaces[10]?.requestCollapse()
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)

        fixture.coordinator.setExternalSurfacePresented(false)

        #expect(fixture.surfaces[10]?.externalSurfaceUpdates == [true, false])
        #expect(fixture.surfaces[20]?.externalSurfaceUpdates.isEmpty == true)
    }

    @Test
    func spotlightReservationDefersPendingGrantUntilDismissal() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.coordinator.setExternalSurfacePresented(true)
        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[10]?.requestCollapse()

        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == false)

        fixture.coordinator.setExternalSurfacePresented(false)
        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == true)
    }

    @Test
    func compactSpotlightReservationRejectsNoticesWithoutReplayingThem() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.coordinator.setExternalSurfacePresented(true)
        fixture.surfaces[10]?.requestCollapse()
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)

        let notice = CoordinatorNoticeFixture(id: "volume")
        fixture.coordinator.showNotice(notice)
        #expect(fixture.surfaces.values.allSatisfy { $0.presentations.last?.notice == nil })

        fixture.coordinator.setExternalSurfacePresented(false)
        #expect(fixture.surfaces.values.allSatisfy { $0.presentations.last?.notice == nil })
        #expect(notice.activations == 0)
    }

    @Test
    func compactCalibrationReservesItsDisplayUntilCompletion() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.coordinator.beginSizeCalibration()
        #expect(fixture.surfaces[10]?.calibrationStartCount == 1)

        fixture.surfaces[20]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.coordinator.expandedDisplayID == nil)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == false)

        fixture.surfaces[10]?.setInteractionHold(
            .calibration,
            active: false
        )
        #expect(fixture.coordinator.expandedDisplayID == 20)
        #expect(fixture.surfaces[20]?.presentations.last?.isExpanded == true)
    }

    @Test
    func rejectedSoftwareCalibrationDoesNotInstallAnInteractionHold() {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20])
        fixture.coordinator.start()
        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)

        fixture.coordinator.beginSizeCalibration()
        #expect(fixture.surfaces[20]?.calibrationStartCount == 1)

        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.coordinator.expandedDisplayID == 10)
    }

    @Test
    func expandedLiveOwnerKeepsLiveShapeMetadataAfterCompactRoutingMoves() {
        let fixture  = DisplayCoordinatorFixture(displayIDs: [10, 20])
        let activity = CoordinatorActivityFixture(id: "music")
        fixture.activityHost.present(activity)
        fixture.coordinator.start()
        fixture.coordinator.updatePreferences(DisplayPresentationPreferences(
            activityMode: .focusedDisplay
        ))
        fixture.surfaces[10]?.requestExpansion(
            activityID: activity.id,
            trigger   : .click,
            generation: 1
        )

        fixture.focus.send(frame: fixture.entry(displayID: 20).snapshot.frame)

        #expect(fixture.surfaces[10]?.presentations.last?.primary == nil)
        #expect(fixture.surfaces[10]?.presentations.last?.expanded === activity)
        #expect(fixture.surfaces[10]?.presentations.last?.expandedIsLiveActivity == true)
        #expect(fixture.surfaces[20]?.presentations.last?.expandedIsLiveActivity == false)
    }

    @Test
    func releasingCompactHoldCollapsesTheCurrentOwnerForPendingHandoff() throws {
        let fixture = DisplayCoordinatorFixture(displayIDs: [10, 20, 30])
        fixture.coordinator.start()
        fixture.surfaces[10]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        fixture.surfaces[20]?.setInteractionHold(
            .drag,
            active: true
        )
        fixture.surfaces[30]?.requestExpansion(
            activityID: nil,
            trigger   : .click,
            generation: 1
        )
        #expect(fixture.surfaces[10]?.closeRequests.isEmpty == true)

        fixture.surfaces[20]?.setInteractionHold(
            .drag,
            active: false
        )
        let closeGeneration = try #require(fixture.surfaces[10]?.closeRequests.last)
        #expect(fixture.coordinator.expandedDisplayID == 10)

        fixture.surfaces[10]?.finishCollapse(generation: closeGeneration)
        #expect(fixture.coordinator.expandedDisplayID == 30)
        #expect(fixture.surfaces[30]?.presentations.last?.isExpanded == true)
    }
}
