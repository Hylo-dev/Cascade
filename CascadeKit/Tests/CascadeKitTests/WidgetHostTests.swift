//
//  WidgetHostTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

/// WidgetHostTests covers the widget lifecycle the host owns: a context stops reaching the host
/// once its widget is suspended or unregistered, and a refresh of one widget rebuilds only that
/// widget's content, never the cached views of the others.
@MainActor
struct WidgetHostTests {

    @Test
    func retainedWidgetContextCannotInvalidateAfterSuspend() {
        let host              = WidgetHost()
        let widget            = WidgetFixture()
        var changes           = 0
        host.onContentChanged = { changes += 1 }
        host.register(widget)
        host.update(state: .open)

        let retained = widget.context
        host.update(state: .closed)
        retained?.setNeedsContent()

        #expect(changes == 0)
        #expect(widget.suspensions == 1)
    }

    @Test
    func unregisterRevokesContextBeforeSuspendingWidget() {
        let host              = WidgetHost()
        let widget            = WidgetFixture()
        var changes           = 0
        host.onContentChanged = { changes += 1 }
        host.register(widget)
        host.update(state: .open)

        let before = changes
        host.unregister(id: widget.id)
        #expect(changes == before + 1)

        widget.context?.setNeedsContent()
        #expect(changes == before + 1)
    }

    @Test
    func refreshingOneWidgetDoesNotRebuildUnaffectedWidgetFactory() {
        let host   = WidgetHost()
        let first  = WidgetFixture(id: "first")
        let second = WidgetFixture(id: "second")
        host.register(first)
        host.register(second)
        host.update(state: .open)

        host.onContentChanged = {
            _ = host.makeContentView(
                interior     : CGRect(x: 0, y: 0, width: 400, height: 120),
                notchWidth   : 100,
                topBandHeight: 30,
                hostHeight   : 120
            )
        }
        _ = host.makeContentView(
            interior     : CGRect(x: 0, y: 0, width: 400, height: 120),
            notchWidth   : 100,
            topBandHeight: 30,
            hostHeight   : 120
        )

        let unaffectedCount = second.factoryCount
        first.context?.setNeedsContent()
        #expect(first.factoryCount == 2)
        #expect(second.factoryCount == unaffectedCount)
    }
}
