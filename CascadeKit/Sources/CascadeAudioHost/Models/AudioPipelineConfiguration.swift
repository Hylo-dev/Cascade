//
//  AudioPipelineConfiguration.swift
//  CascadeKit
//

/// AudioPipelineConfiguration is everything that decides what one app's pipeline looks like: which
/// Core Audio processes it taps, which devices it renders to, and whether the cheaper stream tap
/// applies (only when the one output is the system output, the device the app plays to). Two equal configurations describe the same pipeline, which is how the
/// reconciler knows a change is real and a repeated call is not.
///
/// `processObjectIDs` is kept sorted ascending by whoever builds it, so the same set of helpers
/// always compares equal no matter what order Core Audio listed them in.
public struct AudioPipelineConfiguration: Hashable, Sendable {

    public let processObjectIDs : [UInt32]
    public let outputUIDs       : [String]
    public let streamTap        : Bool

    public init(
        processObjectIDs : [UInt32],
        outputUIDs       : [String],
        streamTap        : Bool
    ) {
        self.processObjectIDs = processObjectIDs
        self.outputUIDs       = outputUIDs
        self.streamTap        = streamTap
    }
}
