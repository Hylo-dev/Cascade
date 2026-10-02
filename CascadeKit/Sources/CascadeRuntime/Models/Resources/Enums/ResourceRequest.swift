//
//  ResourceRequest.swift
//  CascadeKit
//

public enum ResourceRequest: Sendable {

    case state          (bytes: Int)
    case asset          (bytes: Int)
    case temporaryMemory(bytes: Int)
    case diskState      (bytes: Int)
    case diskCache      (bytes: Int)
}
