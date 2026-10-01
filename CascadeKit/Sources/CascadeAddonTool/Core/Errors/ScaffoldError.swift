//
//  ScaffoldError.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

struct ScaffoldError: Error {

    let message: String

    init(_ message: String) { self.message = message }
}
