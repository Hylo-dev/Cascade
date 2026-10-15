//
//  TapLifecycleCounter.swift
//  Cascade
//

#if VOLUME_MONITOR_TESTS

/// TapLifecycleCounter counts what the key tap's observers asked of it.
@MainActor
final class TapLifecycleCounter {

    var refreshes = 0
    var suspends  = 0
    var resumes   = 0
}

#endif
