//
//  PluginComponentServices.swift
//  CascadeKit
//

/// PluginComponentServices is what the kernel's tier-2 components may read beyond their own
/// parameters: the live models their data lives in, which a plugin cannot publish as a document.
/// The router owns one and puts it in the environment of every widget and detail it draws, so a
/// component reads its model from the environment and never reaches for a global. A service the
/// app does not provide is nil, and a component that needs it draws nothing.
@MainActor
public final class PluginComponentServices {

    public let audio: AudioMixerModel?

    public init(audio: AudioMixerModel? = nil) {
        self.audio = audio
    }
}
