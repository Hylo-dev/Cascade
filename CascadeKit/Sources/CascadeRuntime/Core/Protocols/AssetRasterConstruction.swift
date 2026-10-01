//
//  AssetRasterConstruction.swift
//  CascadeKit
//

import CoreGraphics

/// AssetRasterConstruction is the trusted construction boundary, not an addon callback. A nil
/// provider result MUST retain neither context nor provider and cannot schedule a later
/// callback. A builder may drop a successfully built provider before returning nil; the
/// context's one-shot disposal handles that real callback as well as no callback.
protocol AssetRasterConstruction: Sendable {

    func allocate(bytes: Int) -> UnsafeMutableRawPointer?

    func deallocate(
        _ pointer: UnsafeMutableRawPointer,
        bytes    : Int
    )

    func provider(context: AssetRasterProviderContext) -> CGDataProvider?
    func colorSpace() -> CGColorSpace?

    func image(
        layout    : AssetRasterLayout,
        provider  : CGDataProvider,
        colorSpace: CGColorSpace
    ) -> CGImage?
}
