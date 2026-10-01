//
//  PermissionStore.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct PermissionStore {

    struct Entry {

        let value      : HostServicePermission
        let reservation: ResourceReservation
    }

    var entries: [UUID: Entry] = [:]
}
