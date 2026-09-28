import Foundation
import Testing
import CascadeContracts
import CascadeRuntime

func installedFixture(_ name: String, publisher: String = "TEST-ONLY.publisher", digest: String? = nil, enabled: Bool = true) throws -> InstalledAddon {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    let manifest = try AddonManifest.decode(Data(contentsOf: url))
    return try InstalledAddon(
        manifest: manifest,
        verifiedIdentity: VerifiedAddonIdentity(publisher: publisher, addonID: manifest.id),
        digest: digest ?? "test-only-\(manifest.id.rawValue)",
        enabled: enabled
    )
}

func requirement(_ id: String, _ range: String) throws -> AddonRequirement {
    try AddonRequirement(kind: .service, id: id, version: range, bundleID: nil, state: nil, anyOf: nil)
}

func replacing(_ addon: InstalledAddon, id: String? = nil, requires: [AddonRequirement]? = nil, provides: [ProvidedService]? = nil, permissions: [AddonPermission]? = nil, features: [AddonFeature]? = nil) throws -> InstalledAddon {
    let newID = AddonID(rawValue: id ?? addon.manifest.id.rawValue)!
    let manifest = try AddonManifest(manifestVersion: addon.manifest.manifestVersion, id: newID, version: addon.manifest.version, compatibility: addon.manifest.compatibility, execution: addon.manifest.execution, sourceApp: addon.manifest.sourceApp, bundledLibraries: addon.manifest.bundledLibraries, requires: requires ?? addon.manifest.requires, provides: provides ?? addon.manifest.provides, features: features ?? addon.manifest.features, permissions: permissions ?? addon.manifest.permissions, resources: addon.manifest.resources)
    return try InstalledAddon(manifest: manifest, verifiedIdentity: VerifiedAddonIdentity(publisher: addon.verifiedIdentity.publisher, addonID: newID), digest: "test-only-\(newID.rawValue)", enabled: addon.enabled)
}

let emptyEnvironment = HostEnvironment(osVersion: SemanticVersion(14, 0, 0), hostCapabilities: [:], applications: [:], grants: [:], explicitBindings: [])
