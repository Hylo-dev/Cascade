//
//  PluginIDTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginIDTests {

    @Test(arguments: ["com.cascade.clock", "com.example.focus-timer"])
    func acceptsReverseDNSNames(_ name: String) {
        #expect(PluginID(rawValue: name)?.rawValue == name)
    }

    @Test(arguments: ["clock", "com..clock", "1com.cascade", "com.cascade.", ""])
    func rejectsNamesThatAreNotReverseDNS(_ name: String) {
        #expect(PluginID(rawValue: name) == nil)
    }

    @Test
    func rejectsNamesLongerThan255Bytes() {
        let longest = "com." + String(repeating: "a", count: 251)
        let tooLong = "com." + String(repeating: "a", count: 252)

        #expect(PluginID(rawValue: longest) != nil)
        #expect(PluginID(rawValue: tooLong) == nil)
    }

    @Test
    func rejectsAnInvalidNameWhileDecoding() {
        #expect(throws: AddonFailure.self) {
            try JSONDecoder().decode(PluginID.self, from: Data("\"clock\"".utf8))
        }
    }
}
