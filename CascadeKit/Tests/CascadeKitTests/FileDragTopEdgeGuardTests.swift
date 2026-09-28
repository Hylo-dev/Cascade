//
//  FileDragTopEdgeGuardTests.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

@Suite
struct FileDragTopEdgeGuardTests {
    @Test
    func clampsOnlyTheTargetScreensTopEdgeInsideTheShelfBand() throws {
        let primary = CGRect(x: 100, y: 200, width: 1_000, height: 800)
        let geometry = try #require(FileDragTopEdgeGeometry(
            region: CGRect(x: 450, y: 940, width: 200, height: 60),
            screen: primary,
            primaryScreen: primary
        ))

        #expect(geometry.clamped(CGPoint(x: 400, y: 0)) == CGPoint(x: 400, y: 2))
        #expect(geometry.clamped(CGPoint(x: 349, y: 0)) == CGPoint(x: 349, y: 0))
        #expect(geometry.clamped(CGPoint(x: 551, y: 0)) == CGPoint(x: 551, y: 0))
        #expect(geometry.clamped(CGPoint(x: 400, y: 3)) == CGPoint(x: 400, y: 3))
    }

    @Test
    func convertsScreensAboveAndBelowThePrincipalScreen() throws {
        let primary = CGRect(x: 100, y: 200, width: 1_000, height: 800)
        let above = CGRect(x: -500, y: 1_000, width: 800, height: 600)
        let below = CGRect(x: 300, y: -500, width: 900, height: 700)
        let aboveGeometry = try #require(FileDragTopEdgeGeometry(
            region: CGRect(x: -250, y: 1_540, width: 300, height: 60),
            screen: above,
            primaryScreen: primary
        ))
        let belowGeometry = try #require(FileDragTopEdgeGeometry(
            region: CGRect(x: 550, y: 140, width: 300, height: 60),
            screen: below,
            primaryScreen: primary
        ))

        #expect(aboveGeometry.clamped(CGPoint(x: -200, y: -600)) == CGPoint(x: -200, y: -598))
        #expect(belowGeometry.clamped(CGPoint(x: 500, y: 800)) == CGPoint(x: 500, y: 802))
        #expect(aboveGeometry.clamped(CGPoint(x: 500, y: -600)) == CGPoint(x: 500, y: -600))
    }

    @Test
    func rejectsGeometryThatDoesNotReachTheTargetScreensTopEdge() {
        let primary = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        #expect(FileDragTopEdgeGeometry(
            region: CGRect(x: 400, y: 600, width: 200, height: 100),
            screen: primary,
            primaryScreen: primary
        ) == nil)
    }

    @Test
    func mouseUpDisarmsBeforeAnyLaterDragEvent() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let geometry = try #require(FileDragTopEdgeGeometry(
            region: CGRect(x: 400, y: 740, width: 200, height: 60),
            screen: screen,
            primaryScreen: screen
        ))
        var filter = FileDragTopEdgeFilter(geometry: geometry)

        #expect(filter.process(.leftMouseDragged, at: CGPoint(x: 500, y: 0)) == .move(to: CGPoint(x: 500, y: 2)))
        #expect(filter.process(.leftMouseUp, at: CGPoint(x: 500, y: 0)) == .stop)
        #expect(filter.process(.leftMouseDragged, at: CGPoint(x: 500, y: 0)) == .pass)
    }
}
