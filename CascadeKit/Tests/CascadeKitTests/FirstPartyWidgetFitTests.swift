//
//  FirstPartyWidgetFitTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine
@testable import CascadePlugins

/// FirstPartyWidgetFitTests draws each face of the first-party widgets with the kernel's own
/// renderer and holds it to the smallest tile of its size. Under a 38-point notch the grid's
/// main rows are 31 points tall, so a 1x1 tile is 52 by 31, a 2x1 tile 110 by 31 and a 2x2 tile
/// 110 by 68; a face whose natural size is larger would spill over the tile beside it.
@MainActor
struct FirstPartyWidgetFitTests {

    private static let small = CGSize(width: 52, height: 31)
    private static let short = CGSize(width: 110, height: 31)
    private static let large = CGSize(width: 110, height: 68)

    /// size is what a face asks for when nothing constrains it, drawn alone as a document.
    private func size(of face: PluginNode) throws -> CGSize {
        var publisher = PluginRenderFixtures.Publisher()
        let store     = PluginNodeStore(key: PluginRenderFixtures.key, submit: { _ in })
        store.apply(publisher.publish(try PluginDocument(root: face)))

        return NSHostingView(rootView: PluginDocumentView(store: store)).fittingSize
    }

    private func faces(of publication: PluginPublication) throws -> [PluginNode] {
        try #require(publication.document).root.children
    }

    /// fits holds a face to the tile twice: as drawn, and without its own frames, so content
    /// that a fixed frame would hide, spilling past it, counts too.
    private func fits(
        _ face : PluginNode,
        in tile: CGSize
    ) throws -> Bool {
        let unframed = PluginNode(
            face.kind,
            id       : face.id,
            modifiers: face.modifiers.filter { modifier in
                if case .frame = modifier { return false }

                return true
            },
            children : face.children,
            layers   : face.layers
        )

        return try [size(of: face), size(of: unframed)].allSatisfy { size in
            size.width <= tile.width && size.height <= tile.height
        }
    }

    @Test(arguments: [(2026, 2, 14), (2026, 8, 31), (2026, 10, 2)])
    func everyCalendarFaceFitsItsTile(
        year : Int,
        month: Int,
        day  : Int
    ) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale       = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        let date  = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9)))
        let faces = try faces(of: CalendarFace.publication(at: date, in: calendar))

        #expect(try fits(faces[0], in: Self.large))
        #expect(try fits(faces[1], in: Self.small))
    }

    @Test
    func everyProgressFaceFitsItsTile() throws {
        let faces = try faces(of: ProgressFace.publication(for: ProgressPeriods(at: Date.now, calendar: .autoupdatingCurrent)))

        #expect(try fits(faces[0], in: Self.large))
        #expect(try fits(faces[1], in: Self.short))
    }

    /// Every state of the timer, with the most buttons or the longest time it can show.
    @Test
    func everyTimerFaceFitsItsTile() throws {
        let longest = TimerState.longestDuration
        let states: [TimerState] = [
            .idle(duration: 0),
            .idle(duration: 300),
            .idle(duration: longest),
            .running(end: Date.now.addingTimeInterval(longest), duration: longest),
            .paused(remaining: longest, duration: longest),
        ]

        for state in states {
            let faces   = try faces(of: TimerFace.publication(for: state))
            let smaller = faces[1].children

            #expect(try fits(faces[0], in: Self.large))
            #expect(try fits(smaller[0], in: Self.short))
            #expect(try fits(smaller[1], in: Self.small))
        }
    }

    /// A time with a fixed slot shrinks into it rather than being cut short: its widest value, an
    /// hour and more, fits the slot at the smallest scale the face lets it reach. The fit tests
    /// above measure a face's natural size, which a slot hides, so they cannot see this.
    @Test
    func everyTimeFitsItsSlotAtItsSmallestScale() throws {
        let longest   = TimerState.longestDuration
        let documents = try [
            TimerFace.publication(for: .idle(duration: longest)),
            TimerFace.publication(for: .running(end: Date.now.addingTimeInterval(longest), duration: longest)),
            TimerFace.publication(for: .paused(remaining: longest, duration: longest)),
            StopwatchFace.publication(for: .running(since: Date.now, before: 3_725)),
            StopwatchFace.publication(for: .paused(elapsed: 3_725)),
        ].map { try #require($0.document) }
        var slotted = 0

        for document in documents {
            for node in walk(document.root) {
                var font  : PluginFont?
                var factor: Double?
                var slot  : Double?
                for modifier in node.modifiers {
                    switch modifier {
                        case .font(let value)                 : font = value
                        case .minimumScaleFactor(let value)   : factor = value
                        case .frame(let width?, _, _, _, _)   : slot = width
                        default                               : break
                    }
                }
                guard let font, let factor, let slot else { continue }

                let widest = try size(of: PluginNode(.text("1:39:00"), modifiers: [.font(font)])).width
                slotted += 1

                #expect(Double(widest) * factor <= slot)
            }
        }
        #expect(slotted == 10)
    }

    /// Every state of the devices widget, with four devices whose names outrun their rows and
    /// whose charges are full: a name is cut short on its one line, never the row.
    @Test
    func everyDevicesFaceFitsItsTile() throws {
        let long    = "Someone’s Very Long Headphones Name"
        let devices = (0..<4).map { index in
            PluginBluetoothDevice(name: long, symbolName: "antenna.radiowaves.left.and.right", batteryLevel: index == 3 ? nil : 100)
        }
        let states: [PluginBluetoothState] = [
            .baseline(isAvailable: true),
            .baseline(isAvailable: false),
            .baseline(isAvailable: true, connectedDevices: devices),
        ]

        for state in states {
            let faces = try faces(of: DevicesFace.publication(for: state))

            #expect(try fits(faces[0], in: Self.large))
            #expect(try fits(faces[1], in: Self.short))
        }
    }

    @Test
    func everySoundFaceFitsItsTile() throws {
        let states: [PluginVolumeState] = [
            PluginVolumeState(percentage: 100, isMuted: false, announcement: 0),
            PluginVolumeState(percentage: 5, isMuted: false, announcement: 0),
            PluginVolumeState(percentage: 0, isMuted: true, announcement: 0),
        ]

        for state in states {
            let faces = try faces(of: SoundFace.publication(for: state))

            #expect(try fits(faces[0], in: Self.short))
            #expect(try fits(faces[1], in: Self.small))
        }
    }

    @Test
    func everyNetworkFaceFitsItsTile() throws {
        let interfaces: [PluginNetworkInterface] = [.wifi, .ethernet, .cellular, .other, .none]
        let states = interfaces.flatMap { interface in
            [
                PluginNetworkState(isConnected: interface != .none, interface: interface, isExpensive: false, isConstrained: false),
                PluginNetworkState(isConnected: true, interface: interface, isExpensive: true, isConstrained: false),
                PluginNetworkState(isConnected: true, interface: interface, isExpensive: true, isConstrained: true),
            ]
        }

        for state in states {
            let faces = try faces(of: NetworkFace.publication(for: state))

            #expect(try fits(faces[0], in: Self.short))
            #expect(try fits(faces[1], in: Self.small))
        }
    }

    /// A percentage has a slot of its own and is never cut short or shrunk: its widest value,
    /// 100%, fits the slot whole in the font the face gives it.
    @Test
    func everyPercentageFitsItsSlotWhole() throws {
        let full      = PluginBluetoothDevice(name: "AirPods Pro", symbolName: "airpodspro", batteryLevel: 100)
        let documents = try [
            DevicesFace.publication(for: .baseline(isAvailable: true, connectedDevices: [full])),
            SoundFace.publication(for: PluginVolumeState(percentage: 100, isMuted: false, announcement: 0)),
        ].map { try #require($0.document) }
        var slotted = 0

        for document in documents {
            for node in walk(document.root) {
                guard case .text("100%") = node.kind else { continue }

                var font: PluginFont?
                var slot: Double?
                for modifier in node.modifiers {
                    switch modifier {
                        case .font(let value)              : font = value
                        case .frame(let width?, _, _, _, _): slot = width
                        default                            : break
                    }
                }
                let widest = try size(of: PluginNode(.text("100%"), modifiers: [.font(try #require(font))])).width
                slotted += 1

                #expect(Double(widest) <= (try #require(slot)))
            }
        }
        #expect(slotted == 4)
    }

    /// A symbol with a slot of its own fits it whole, for every symbol a face may show: each the
    /// Bluetooth source names a device with, each speaker, and each link. A slot narrower than
    /// its symbol would let the symbol spill over the name or the reading beside it.
    @Test
    func everySymbolFitsItsSlot() throws {
        let symbols = [
            "antenna.radiowaves.left.and.right", "camera", "computermouse", "desktopcomputer",
            "gamecontroller", "headphones", "keyboard", "smartphone", "speaker.wave.2",
        ]
        let devices = symbols.map { symbol in
            PluginBluetoothDevice(name: "Device", symbolName: symbol, batteryLevel: 50)
        }
        let links: [PluginNetworkInterface] = [.wifi, .ethernet, .cellular, .other]
        let publications = try stride(from: 0, to: devices.count, by: PluginBluetoothDevice.maximumCount).map { start in
            try DevicesFace.publication(for: .baseline(isAvailable: true, connectedDevices: Array(devices[start...].prefix(4))))
        }
        + [0, 20, 50, 100].map { level in
            try SoundFace.publication(for: PluginVolumeState(percentage: level, isMuted: false, announcement: 0))
        }
        + [try SoundFace.publication(for: PluginVolumeState(percentage: 0, isMuted: true, announcement: 0))]
        + links.map { link in
            try NetworkFace.publication(for: PluginNetworkState(isConnected: true, interface: link, isExpensive: false, isConstrained: false))
        }
        + [try NetworkFace.publication(for: PluginNetworkState(isConnected: false, interface: .none, isExpensive: false, isConstrained: false))]
        var slotted = Set<String>()

        for publication in publications {
            for node in walk(try #require(publication.document).root) {
                guard case .symbol(let name) = node.kind else { continue }

                var font: PluginFont?
                var slot: Double?
                for modifier in node.modifiers {
                    switch modifier {
                        case .font(let value)              : font = value
                        case .frame(let width?, _, _, _, _): slot = width
                        default                            : break
                    }
                }
                guard let font, let slot else { continue }

                let width = try size(of: PluginNode(.symbol(name: name), modifiers: [.font(font)])).width
                slotted.insert(name)

                #expect(Double(width) <= slot, "\(name) is \(width) points in a \(slot)-point slot")
            }
        }
        #expect(slotted.isSuperset(of: symbols + ["speaker.wave.3.fill", "wifi", "cable.connector", "network", "wifi.slash"]))
    }

    /// Every world clock face with no city marked, with every city a day ahead and with every
    /// city a day behind: the tall face holds three rows and the short one two columns.
    @Test(arguments: [("Europe/Rome", 12), ("Pacific/Honolulu", 20), ("Pacific/Kiritimati", 3)])
    func everyWorldClockFaceFitsItsTile(
        zone: String,
        hour: Int
    ) throws {
        let (date, calendar) = try worldClockMoment(zone: zone, hour: hour)
        let faces            = try faces(of: WorldClockFace.publication(at: date, in: calendar))

        #expect(try fits(faces[0], in: Self.large))
        #expect(try fits(faces[1], in: Self.short))
    }

    /// Every name, mark and time of the world clock fits its slot rather than being cut short:
    /// every name and mark whole, in English and in Italian, New York and Yesterday the widest,
    /// and a 24-hour time whole; a twelve-hour time, the widest a minute can be, at the smallest
    /// scale the face lets it reach. A slot is the nearest fixed width at or above the text,
    /// which in these faces no sibling shares.
    @Test
    func everyWorldClockWordFitsItsSlot() throws {
        let names   = ["New York", "London", "Londra", "Tokyo"]
        let marks   = ["Tomorrow", "Yesterday", "Domani", "Ieri"]
        var slotted = 0

        for (zone, hour) in [("Pacific/Honolulu", 20), ("Pacific/Kiritimati", 3)] {
            let (date, calendar) = try worldClockMoment(zone: zone, hour: hour)
            let document         = try #require(try WorldClockFace.publication(at: date, in: calendar).document)

            for (node, slot) in slots(in: document.root, slot: nil) {
                var font  : PluginFont?
                var factor: Double?
                for modifier in node.modifiers {
                    switch modifier {
                        case .font(let value)              : font = value
                        case .minimumScaleFactor(let value): factor = value
                        default                            : break
                    }
                }
                guard let font, let factor, let slot else { continue }

                let candidates: [(text: String, scale: Double)]
                switch node.kind {
                    case .text(let text): candidates = (names.contains(text) ? names : marks).map { ($0, 1) }
                    case .clock         : candidates = [("23:59", 1), ("12:59 AM", factor), ("12:59 PM", factor)]
                    default             : continue
                }

                for candidate in candidates {
                    let width = try size(of: PluginNode(.text(candidate.text), modifiers: [.font(font)])).width
                    slotted += 1

                    #expect(Double(width) * candidate.scale <= slot, "\(candidate.text) is \(width) points in a \(slot)-point slot")
                }
            }
        }
        #expect(slotted == 2 * (10 * 4 + 5 * 3))
    }

    /// worldClockMoment is a day at an hour in a zone, Rome's at noon with every city on the same
    /// day, Honolulu's in the evening with every city a day ahead, Kiritimati's in the small hours
    /// with every city a day behind.
    private func worldClockMoment(
        zone: String,
        hour: Int
    ) throws -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: hour)))

        return (date, calendar)
    }

    /// slots pairs every node with the nearest fixed width at or above it.
    private func slots(
        in node: PluginNode,
        slot   : Double?
    ) -> [(PluginNode, Double?)] {
        var own = slot
        for modifier in node.modifiers {
            if case .frame(let width?, _, _, _, _) = modifier { own = width }
        }

        return [(node, own)] + (node.children + node.layers).flatMap { slots(in: $0, slot: own) }
    }

    private func walk(_ node: PluginNode) -> [PluginNode] {
        [node] + (node.children + node.layers).flatMap(walk)
    }

    @Test
    func everyStopwatchFaceFitsItsTile() throws {
        let states: [StopwatchState] = [
            .idle,
            .running(since: Date.now, before: 3_725),
            .paused(elapsed: 3_725),
        ]

        for state in states {
            let faces = try faces(of: StopwatchFace.publication(for: state))

            #expect(try fits(faces[0], in: Self.short))
            #expect(try fits(faces[1], in: Self.small))
        }
    }
}
