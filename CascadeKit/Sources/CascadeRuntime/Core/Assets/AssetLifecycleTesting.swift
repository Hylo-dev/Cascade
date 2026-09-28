//
//  AssetLifecycleTesting.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

#if DEBUG

enum AssetLifecycleTesting {
    @TaskLocal static var observer: (any AssetLifecycleTestObserver)?

    static func observer(for governor: ResourceGovernor) -> (any AssetLifecycleTestObserver)? {
        guard let observer, observer.governor === governor else { return nil }
        return observer
    }
}

#endif
