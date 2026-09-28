//
//  FileShelfScrollNavigation.swift
//  Cascade
//

nonisolated enum FileShelfScrollNavigation: Equatable {

    case open
    case close(expectedDirection: FileShelfScrollDirection)
}
