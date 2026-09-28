//
//  ResourceRequest.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public enum ResourceRequest: Sendable {
    case publication(Publication.Kind)
    case job, command, provider, scene
    case state(bytes: Int), asset(bytes: Int), temporaryMemory(bytes: Int)
    case diskState(bytes: Int), diskCache(bytes: Int)
}
