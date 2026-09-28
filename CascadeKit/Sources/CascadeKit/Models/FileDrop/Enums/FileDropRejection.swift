//
//  FileDropRejection.swift
//  CascadeKit
//

enum FileDropRejection: String {

    case sourceDoesNotCopy
    case oversizedBatch
    case promisedFile
    case unsupportedItem
    case unreadableFile
}
