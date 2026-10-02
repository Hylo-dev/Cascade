//
//  ResourceDimension.swift
//  CascadeKit
//

public enum ResourceDimension: Hashable, Sendable {

    case retainedStateBytes
    case assetBytes
    case admittedMemoryBytes
    case diskStateBytes
    case diskCacheBytes
    case diskBytes
}
