//
//  PluginHostSigningTests.swift
//  CascadeKit
//

import CascadePluginHost
import Security
import Testing

@Suite
struct PluginHostSigningTests {

    @Test
    func theRequirementCompilesAndNamesTheIdentifierAndTeam() throws {
        let text = try #require(PluginHostSigning.requirement(identifier: "hylo.Cascade", team: "8KZQJ4JUGS"))
        var requirement: SecRequirement?

        #expect(text == #"anchor apple generic and identifier "hylo.Cascade" and certificate leaf[subject.OU] = "8KZQJ4JUGS""#)
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
    }

    @Test
    func anAdHocBuildHasNoRequirement() {
        #expect(PluginHostSigning.requirement(identifier: "hylo.Cascade", team: nil) == nil)
        #expect(PluginHostSigning.requirement(identifier: "hylo.Cascade", team: "") == nil)
    }
}
