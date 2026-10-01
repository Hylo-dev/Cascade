//
//  AssetRasterLayout.swift
//  CascadeKit
//

import CascadeContracts

struct AssetRasterLayout: Sendable {

    let width    : Int
    let height   : Int
    let rowBytes : Int
    let byteCount: Int

    init(
        width    : Int,
        height   : Int,
        byteCount: Int
    ) throws {
        let (pixels, pixelOverflow)  = width.multipliedReportingOverflow(by: height)
        let (rowBytes, rowOverflow)  = width.multipliedReportingOverflow(by: 4)
        let (required, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)

        guard width > 0,
              height > 0,
              !pixelOverflow,
              !rowOverflow,
              !byteOverflow,
              pixels <= 1_000_000,
              byteCount == required
        else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The raster must contain at most one million tightly packed RGBA8 pixels."
            )
        }

        self.width     = width
        self.height    = height
        self.rowBytes  = rowBytes
        self.byteCount = required
    }
}
