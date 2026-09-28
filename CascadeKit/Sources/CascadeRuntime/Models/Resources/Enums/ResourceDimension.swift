//
//  ResourceDimension.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public enum ResourceDimension: Hashable, Sendable {
    case publications, activities, notices, jobs, commands, providers, scenes
    case retainedStateBytes, assetBytes, admittedMemoryBytes, diskStateBytes, diskCacheBytes, diskBytes
}
