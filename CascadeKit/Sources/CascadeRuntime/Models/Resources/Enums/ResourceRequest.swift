//
//  ResourceRequest.swift
//  CascadeKit
//

import CascadeContracts

public enum ResourceRequest: Sendable {

    case publication    (Publication.Kind)
    case job
    case command
    case provider
    case scene
    case state          (bytes: Int)
    case asset          (bytes: Int)
    case temporaryMemory(bytes: Int)
    case diskState      (bytes: Int)
    case diskCache      (bytes: Int)
}
