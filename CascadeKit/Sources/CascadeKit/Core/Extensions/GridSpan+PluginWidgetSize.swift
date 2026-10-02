//
//  GridSpan+PluginWidgetSize.swift
//  CascadeKit
//

import CascadeContracts

extension GridSpan {

    /// init(_:) places a plugin widget on today's fourteen-column grid until the layout
    /// sub-project brings slots: each column of the manifest's size takes two grid columns, so
    /// a 2x1 widget keeps the 4×1 footprint of the clock it replaces.
    init(_ size: PluginWidgetSize) {
        self.init(columns: size.columns * 2, rows: size.rows)
    }
}
