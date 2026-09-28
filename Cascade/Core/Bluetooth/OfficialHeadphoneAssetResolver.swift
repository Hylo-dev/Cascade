//
//  OfficialHeadphoneAssetResolver.swift
//  Cascade
//

import Foundation

/// Apple's CoreBluetoothUI catalog is the source of product identity, including
/// newer variants that share hardware artwork. BluetoothUIService owns the
/// corresponding banner turntables. Reading their resource files uses public
/// Foundation APIs; no private framework code is loaded or called.
nonisolated struct OfficialHeadphoneAssetResolver: OfficialHeadphoneAssetResolving {

    let catalogDirectory: URL
    let bannerDirectory : URL

    init(
        catalogDirectory: URL = URL(
            fileURLWithPath: "/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Versions/A/Resources"
        ),
        bannerDirectory : URL = URL(
            fileURLWithPath: "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources"
        )
    ) {
        self.catalogDirectory = catalogDirectory
        self.bannerDirectory  = bannerDirectory
    }

    func resolve(
        productID: UInt16,
        colorID  : UInt8?
    ) throws -> OfficialHeadphoneAsset? {
        let entries = try readCatalog()
        guard let entry = entries[productID] else { return nil }

        let imageName = entry.imageName(for: colorID)
        guard isSafeImageName(imageName) else { return nil }

        let imageURL = catalogDirectory.appendingPathComponent(imageName)
        guard isBoundedFile(imageURL, maximumBytes: 4_194_304) else { return nil }

        // For example, Apple's catalog maps both Pro 2 connectors to B698.icns
        // and both AirPods 4 variants to B768.icns. Reuse an existing turntable
        // only when Apple itself specifies identical artwork for the variant.
        let aliases = entries.keys.filter {
            $0 != productID && entries[$0]?.imageName(for: colorID) == imageName
        }.sorted()
        let hasVerifiedColor = colorID.flatMap { entry.colors[$0] } != nil
        for candidate in [productID] + aliases {
            if let movieURL = movieURL(
                productID: candidate,
                colorID  : hasVerifiedColor ? colorID : nil
            ) {
                return OfficialHeadphoneAsset(imageURL: imageURL, movieURL: movieURL)
            }
        }

        return OfficialHeadphoneAsset(imageURL: imageURL, movieURL: nil)
    }

    private func movieURL(
        productID: UInt16,
        colorID  : UInt8?
    ) -> URL? {
        let baseName  = "Banner-PID-\(productID)"
        let directory = bannerDirectory.appendingPathComponent(baseName + "-mov")

        let names: [String]
        if let colorID {
            names = ["\(baseName)-\(colorID)-Loop.mov"]
        } else {
            names = ["\(baseName)-Loop.mov", "\(baseName)-default-Loop.mov"]
        }

        return names.map { directory.appendingPathComponent($0) }.first {
            isBoundedFile($0, maximumBytes: 8_388_608)
        }
    }

    private struct Entry {

        let imageName: String
        let colors   : [UInt8: String]

        func imageName(for colorID: UInt8?) -> String {
            colorID.flatMap { colors[$0] } ?? imageName
        }
    }

    private func readCatalog() throws -> [UInt16: Entry] {
        guard FileManager.default.fileExists(atPath: catalogDirectory.path) else { return [:] }

        let files = try FileManager.default.contentsOfDirectory(
            at                        : catalogDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options                   : [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasPrefix("AssetPaths") && $0.pathExtension == "plist"
        }.sorted {
            // Specific catalogs override legacy entries in AssetPaths.plist.
            if $0.lastPathComponent == "AssetPaths.plist" { return true }
            if $1.lastPathComponent == "AssetPaths.plist" { return false }
            return $0.lastPathComponent < $1.lastPathComponent
        }

        var entries: [UInt16: Entry] = [:]
        for file in files.prefix(32) {
            try Task.checkCancellation()
            guard isBoundedFile(file, maximumBytes: 262_144) else { continue }

            let data = try Data(contentsOf: file)
            guard let dictionary = try PropertyListSerialization.propertyList(
                from  : data,
                format: nil
            ) as? [String: [String: Any]] else { continue }

            for (key, value) in dictionary.prefix(256) {
                guard key.hasPrefix("0x"),
                      let identifier = UInt16(key.dropFirst(2), radix: 16),
                      let name = (value["DisplayName"] ?? value["Name"]) as? String,
                      name.hasPrefix("AirPods"),
                      let imageName = value["ImageName"] as? String
                else { continue }

                var colors: [UInt8: String] = [:]
                if let colorNames = value["Color"] as? [String: String] {
                    for (color, filename) in colorNames.prefix(32) {
                        guard color.hasPrefix("0x"),
                              let code = UInt8(color.dropFirst(2), radix: 16)
                        else { continue }

                        colors[code] = filename
                    }
                }
                entries[identifier] = Entry(imageName: imageName, colors: colors)
            }
        }

        return entries
    }

    private func isSafeImageName(_ name: String) -> Bool {
        name.count < 160
            && (name as NSString).lastPathComponent == name
            && ["png", "icns", "tiff"].contains((name as NSString).pathExtension.lowercased())
    }

    private func isBoundedFile(
        _ url       : URL,
        maximumBytes: Int
    ) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let bytes = values.fileSize
        else { return false }

        return bytes > 0 && bytes <= maximumBytes
    }
}
