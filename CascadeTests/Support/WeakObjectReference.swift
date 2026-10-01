//
//  WeakObjectReference.swift
//  Cascade
//

import CascadeContracts
import CascadeRuntime
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Cascade

final class WeakObjectReference {

    weak var value: AnyObject?

    init(_ value: AnyObject?) { self.value = value }
}
