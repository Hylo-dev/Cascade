//
//  AudioProcessGroupingTests.swift
//  CascadeKit
//

import CascadeAudioHost
import CascadeContracts
import Foundation
import Testing

@Suite
struct AudioProcessGroupingTests {

    private static let chromeApp = "/Applications/Google Chrome.app"

    private static let bundleIDsByAppPath: [String: String] = [
        "/Applications/Google Chrome.app": "com.google.Chrome",
        "/Applications/Safari.app"       : "com.apple.Safari",
        "/Applications/Music.app"        : "com.apple.Music",
    ]

    private static func bundleID(ofApp appPath: String) -> String? {
        bundleIDsByAppPath[appPath]
    }

    private static func record(
        objectID : UInt32,
        pid      : Int32,
        bundleID : String?,
        path     : String?
    ) -> AudioProcessRecord {
        AudioProcessRecord(
            objectID        : objectID,
            pid             : pid,
            bundleID        : bundleID,
            executablePath  : path,
            isRunningOutput : true
        )
    }

    @Test
    func chromeHelpersGroupUnderChrome() throws {
        let helperDirectory = "\(Self.chromeApp)/Contents/Frameworks/Google Chrome Framework.framework"
            + "/Versions/130.0.0.0/Helpers"

        let processes = [
            Self.record(
                objectID : 1,
                pid      : 100,
                bundleID : "com.google.Chrome",
                path     : "\(Self.chromeApp)/Contents/MacOS/Google Chrome"
            ),
            Self.record(
                objectID : 2,
                pid      : 101,
                bundleID : "com.google.Chrome.helper.Renderer",
                path     : "\(helperDirectory)/Google Chrome Helper (Renderer).app/Contents/MacOS/"
                    + "Google Chrome Helper (Renderer)"
            ),
            Self.record(
                objectID : 3,
                pid      : 102,
                bundleID : "com.google.Chrome.helper",
                path     : "\(helperDirectory)/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
            ),
        ]

        let groups = AudioProcessGrouping.group(processes, bundleIDOfApp: Self.bundleID(ofApp:))

        let chrome = try AudioAppIdentity(bundleID: "com.google.Chrome")
        #expect(groups.count == 1)
        #expect(groups[chrome]?.map(\.pid) == [100, 101, 102])
    }

    @Test
    func braveAudioHelperGroupsUnderItsOutermostApp() throws {
        let braveApp = "/Applications/Brave Browser.app"
        let helper   = Self.record(
            objectID : 9,
            pid      : 900,
            bundleID : "com.brave.Browser.helper",
            path     : "\(braveApp)/Contents/Frameworks/Brave Browser Framework.framework/Versions/130/"
                + "Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper"
        )

        let groups = AudioProcessGrouping.group(
            [helper],
            bundleIDOfApp: { $0 == braveApp ? "com.brave.Browser" : nil }
        )

        let brave = try AudioAppIdentity(bundleID: "com.brave.Browser")
        #expect(groups[brave]?.map(\.pid) == [900])
    }

    @Test
    func responsibleAppHookGroupsAProcessOutsideItsApp() throws {
        let webKitGPU = Self.record(
            objectID : 4,
            pid      : 200,
            bundleID : "com.apple.WebKit.GPU",
            path     : "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
                + "com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        )

        let groups = AudioProcessGrouping.group(
            [webKitGPU],
            bundleIDOfApp      : Self.bundleID(ofApp:),
            responsibleAppPath : { $0 == 200 ? "/Applications/Safari.app" : nil }
        )

        let safari = try AudioAppIdentity(bundleID: "com.apple.Safari")
        #expect(groups.count == 1)
        #expect(groups[safari]?.map(\.pid) == [200])
    }

    @Test
    func theEnclosingAppWinsOverTheResponsibleApp() throws {
        let music = Self.record(
            objectID : 5,
            pid      : 300,
            bundleID : "com.apple.Music",
            path     : "/Applications/Music.app/Contents/MacOS/Music"
        )

        let groups = AudioProcessGrouping.group(
            [music],
            bundleIDOfApp      : Self.bundleID(ofApp:),
            responsibleAppPath : { _ in "/Applications/Safari.app" }
        )

        let identity = try AudioAppIdentity(bundleID: "com.apple.Music")
        #expect(groups.keys.map(\.bundleID) == [identity.bundleID])
    }

    @Test
    func aProcessOutsideAnyAppFallsBackToItsOwnBundleID() throws {
        let daemon = Self.record(
            objectID : 6,
            pid      : 400,
            bundleID : "com.example.daemon",
            path     : "/usr/local/bin/exampled"
        )

        let groups = AudioProcessGrouping.group([daemon], bundleIDOfApp: Self.bundleID(ofApp:))

        let identity = try AudioAppIdentity(bundleID: "com.example.daemon")
        #expect(groups[identity]?.map(\.pid) == [400])
    }

    @Test
    func processWithoutPathOrBundleIsExcluded() {
        let anonymous = Self.record(objectID: 7, pid: 500, bundleID: nil, path: nil)
        let unknownApp = Self.record(
            objectID : 8,
            pid      : 501,
            bundleID : nil,
            path     : "/Applications/Unknown.app/Contents/MacOS/Unknown"
        )

        let groups = AudioProcessGrouping.group(
            [anonymous, unknownApp],
            bundleIDOfApp: Self.bundleID(ofApp:)
        )

        #expect(groups.isEmpty)
    }

    @Test
    func twoPIDsOfOneAppShareOneIdentity() throws {
        let firstProcess = Self.record(
            objectID : 10,
            pid      : 600,
            bundleID : "com.apple.Music",
            path     : "/Applications/Music.app/Contents/MacOS/Music"
        )
        let secondProcess = Self.record(
            objectID : 11,
            pid      : 601,
            bundleID : "com.apple.Music",
            path     : "/Applications/Music.app/Contents/MacOS/Music"
        )

        let groups = AudioProcessGrouping.group(
            [firstProcess, secondProcess],
            bundleIDOfApp: Self.bundleID(ofApp:)
        )

        let music = try AudioAppIdentity(bundleID: "com.apple.Music")
        #expect(groups.count == 1)
        #expect(groups[music]?.map(\.objectID) == [10, 11])
    }

    @Test
    func outermostAppOfAPathWithoutAppIsNil() {
        #expect(AudioProcessGrouping.outermostApp(of: "/usr/local/bin/exampled") == nil)
        #expect(AudioProcessGrouping.outermostApp(of: "") == nil)
    }

    @Test
    func outermostAppIsTheFirstAppComponentOfThePath() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/x"

        #expect(AudioProcessGrouping.outermostApp(of: path) == "/Applications/Google Chrome.app")
    }
}
