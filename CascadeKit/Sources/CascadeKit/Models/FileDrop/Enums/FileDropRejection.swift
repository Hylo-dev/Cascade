//
//  FileDropRejection.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CascadePresentation
import OSLog
import QuartzCore
import SwiftUI

enum FileDropRejection: String {
    case sourceDoesNotCopy
    case oversizedBatch
    case promisedFile
    case unsupportedItem
    case unreadableFile
}
