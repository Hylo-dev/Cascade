//
//  NetworkFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// NetworkFace is the network widget's document, a face for the 2x1 tile and one for the 1x1
/// tile, the wider first. The link is a symbol and a word, Wi-Fi, Ethernet, Cellular or, for
/// any other link, Connected; offline, a struck Wi-Fi symbol and the word dimmed. A constrained
/// path, as Low Data Mode makes it, is marked Limited, and an expensive one, as a hotspot is,
/// Metered, in yellow; a path that is both is marked Limited, the stronger of the two, and
/// VoiceOver reads both.
///
/// Under a 38-point notch a 2x1 tile is 110 by 31 points and a 1x1 tile 52 by 31. The 2x1 face
/// is 100 points wide, the symbol beside a 12-point word with the mark below it, 26 points tall.
/// The 1x1 face is the symbol above one 8.5-point word, 48 points wide; its symbol already names
/// the link, so the word is the mark when there is one. Every word shrinks into a fixed width
/// rather than spill out of it, and the fixed width is also what chooses the face: ViewThatFits
/// measures a face with the tile's height already given.
enum NetworkFace {

    static let mediumWidth = 100.0

    private static let mediumPadding = 8.0
    private static let symbolWidth   = 22.0
    private static let gap           = 6.0
    private static let smallWidth    = 48.0

    private static let yellow = PluginColor(red: 1, green: 0.82, blue: 0.27)

    static func publication(for state: PluginNetworkState) throws -> PluginPublication {
        try PluginPublication(
            feature : NetworkPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .horizontal) {

                    medium(state)

                    small(state)
                }
                .accessibilityLabel(([word(of: state)] + marks(of: state)).joined(separator: ", "))
            )
        )
    }

    /// medium is the 2x1 face: the symbol beside the word, and the mark below the word.
    private static func medium(_ state: PluginNetworkState) -> PluginNode {
        HStack(spacing: gap) {

            Image(systemName: symbol(of: state))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tint(of: state))
                .frame(width: symbolWidth)

            VStack(alignment: .leading, spacing: 0) {

                Text(word(of: state))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(of: state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let mark = marks(of: state).first {
                    Text(mark)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: mediumWidth - 2 * mediumPadding - symbolWidth - gap, alignment: .leading)
        }
        .padding(.horizontal, mediumPadding)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the symbol above the mark, or above the word when there is none.
    private static func small(_ state: PluginNetworkState) -> PluginNode {
        let mark = marks(of: state).first

        return VStack(spacing: 1) {

            Image(systemName: symbol(of: state))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint(of: state))

            Text(mark ?? word(of: state))
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(mark == nil ? tint(of: state) : yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: smallWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func symbol(of state: PluginNetworkState) -> String {
        guard state.isConnected else { return "wifi.slash" }

        switch state.interface {
            case .wifi        : return "wifi"
            case .ethernet    : return "cable.connector"
            case .cellular    : return "antenna.radiowaves.left.and.right"
            case .other, .none: return "network"
        }
    }

    private static func word(of state: PluginNetworkState) -> String {
        guard state.isConnected else { return String(localized: "Offline", table: "Plugins", bundle: .module) }

        switch state.interface {
            case .wifi        : return String(localized: "Wi-Fi", table: "Plugins", bundle: .module)
            case .ethernet    : return String(localized: "Ethernet", table: "Plugins", bundle: .module)
            case .cellular    : return String(localized: "Cellular", table: "Plugins", bundle: .module)
            case .other, .none: return String(localized: "Connected", table: "Plugins", bundle: .module)
        }
    }

    /// marks are what the system says of a working path, the stronger first; an offline path has
    /// none.
    private static func marks(of state: PluginNetworkState) -> [String] {
        guard state.isConnected else { return [] }

        var marks: [String] = []
        if state.isConstrained { marks.append(String(localized: "Limited", table: "Plugins", bundle: .module)) }
        if state.isExpensive { marks.append(String(localized: "Metered", table: "Plugins", bundle: .module)) }

        return marks
    }

    private static func tint(of state: PluginNetworkState) -> PluginColor {
        state.isConnected ? .white : .white.opacity(0.55)
    }
}
