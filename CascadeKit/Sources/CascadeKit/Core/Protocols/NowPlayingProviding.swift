//
//  NowPlayingProviding.swift
//  CascadeKit
//

/// NowPlayingProviding is the seam for Music, Spotify or a system Now Playing
/// adapter. Start emits the current snapshot and subsequent real changes; nil
/// ends a session. Stop finishes the stream and releases source subscriptions.
@MainActor
public protocol NowPlayingProviding: AnyObject {

    func start() -> AsyncStream<NowPlayingSnapshot?>
    func stop()
    func send(_ command: MediaCommand) async throws
}
