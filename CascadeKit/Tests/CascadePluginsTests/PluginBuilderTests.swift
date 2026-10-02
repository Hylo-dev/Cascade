//
//  PluginBuilderTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Testing

/// PluginBuilderTests checks that the SwiftUI-shaped builder writes the same trees a plugin
/// would otherwise spell out node by node, so a plugin can switch to it without changing what
/// the kernel draws.
@Suite
struct PluginBuilderTests {

    /// handBuiltMusicRow is the spec's compact Music row written node by node, as the contract
    /// fixtures write it.
    private func handBuiltMusicRow(isPlaying: Bool) -> PluginNode {
        PluginNode(
            .hStack(alignment: .center, spacing: 8),
            children: [
                PluginNode(
                    .asset(id: "artwork"),
                    modifiers: [
                        .frame(width: 32, height: 32, maxWidth: nil, maxHeight: nil, alignment: .center),
                        .clipShape(.roundedRectangle(cornerRadius: 6)),
                    ]
                ),
                PluginNode(
                    .vStack(alignment: .leading, spacing: nil),
                    children: [
                        PluginNode(
                            .text("Song"),
                            modifiers: [.font(PluginFont(style: .headline)), .lineLimit(1)]
                        ),
                        PluginNode(
                            .text("Artist"),
                            modifiers: [.font(PluginFont(style: .caption)), .foregroundStyle(.hierarchical(.secondary))]
                        ),
                    ]
                ),
                PluginNode(.spacer(minLength: nil)),
                PluginNode(
                    .toggle(isOn: isPlaying, action: "togglePlayback"),
                    modifiers: [.contentTransition(.symbolEffect)],
                    children : [PluginNode(.symbol(name: isPlaying ? "pause.fill" : "play.fill"))]
                ),
            ]
        )
    }

    private func musicRow(isPlaying: Bool) -> PluginNode {
        HStack(spacing: 8) {

            Image(asset: "artwork")
                .frame(width: 32, height: 32)
                .clipShape(.roundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading) {

                Text("Song")
                    .font(.headline)
                    .lineLimit(1)

                Text("Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(isOn: isPlaying, action: "togglePlayback") {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .contentTransition(.symbolEffect)
        }
    }

    @Test
    func theMusicRowWrittenWithTheBuilderIsTheTreeWrittenByHand() {
        #expect(musicRow(isPlaying: true) == handBuiltMusicRow(isPlaying: true))
        #expect(musicRow(isPlaying: false) == handBuiltMusicRow(isPlaying: false))
    }

    @Test
    func anIfAddsItsChildOnlyWhenItHolds() {
        func row(showsBolt: Bool) -> PluginNode {
            HStack {

                Text("82%")

                if showsBolt {
                    Image(systemName: "bolt.fill")
                }
            }
        }

        #expect(row(showsBolt: true).children.map(\.kind) == [.text("82%"), .symbol(name: "bolt.fill")])
        #expect(row(showsBolt: false).children.map(\.kind) == [.text("82%")])
    }

    @Test
    func anIfElseAddsTheChildOfTheBranchThatHolds() {
        func stack(isMuted: Bool) -> PluginNode {
            VStack {

                if isMuted {
                    Text("Muted")
                } else {
                    Text("Volume")

                    Spacer()
                }
            }
        }

        #expect(stack(isMuted: true).children.map(\.kind) == [.text("Muted")])
        #expect(stack(isMuted: false).children.map(\.kind) == [.text("Volume"), .spacer(minLength: nil)])
    }

    @Test
    func aForLoopAddsAChildForEveryElement() {
        let stack = ZStack {
            for name in ["a", "b", "c"] {
                Text(name)
            }
        }

        #expect(stack.children.map(\.kind) == [.text("a"), .text("b"), .text("c")])
    }

    @Test
    func aComponentDropsTheParametersThatAreNil() {
        let percentage: Int? = nil

        let battery = Component(
            id        : "power.battery",
            version   : 1,
            parameters: [
                "isCharging": .bool(true),
                "percentage": percentage.map { PluginValue.number(Double($0)) },
            ]
        )

        #expect(battery.kind == .component(id: "power.battery", version: 1, parameters: ["isCharging": .bool(true)]))
    }

    @Test
    func anOverlayAddsItsModifierAndItsLayer() {
        let single = Circle()
            .overlay(alignment: .topTrailing) {
                Text("1")
            }
        let several = Circle()
            .overlay {
                Text("1")

                Text("2")
            }

        #expect(single.modifiers == [.overlay(alignment: .topTrailing)])
        #expect(single.layers == [PluginNode(.text("1"))])
        #expect(several.modifiers == [.overlay(alignment: .center)])
        #expect(
            several.layers == [
                PluginNode(.zStack(alignment: .center), children: [PluginNode(.text("1")), PluginNode(.text("2"))]),
            ]
        )
    }

    @Test
    func aFrameLeavesEveryArgumentItIsNotGivenNil() {
        let filled = Spacer()
            .frame(maxWidth: .infinity)

        #expect(
            filled.modifiers == [
                .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: nil, alignment: .center),
            ]
        )
    }

    @Test
    func idSetsTheNodesIdentity() {
        let text = Text("12:00")
            .font(.title)
            .id("time")

        #expect(text.id == "time")
        #expect(text.modifiers == [.font(PluginFont(style: .title))])
    }
}
