//
//  NativeBluetoothNoticePolicyChecks.swift
//  Cascade
//

#if BLUETOOTH_NOTICE_POLICY_TESTS
import Foundation

/// NativeBluetoothNoticePolicyChecks exercises the selective policy without system permissions.
@main
struct NativeBluetoothNoticePolicyChecks {

    static func main() {
        let now  = Date(timeIntervalSince1970: 100)
        let hint = BluetoothNoticeConnectionHint(
            deviceName: "Studio Buds",
            expiresAt : Date(timeIntervalSince1970: 106)
        )

        func accepts(
            _ texts    : [String],
            isModal    : Bool = false,
            hasControls: Bool = false,
            closeCount : Int = 1,
            isComplete : Bool = true,
            bundleID   : String = "com.apple.controlcenter",
            width      : Double = 350,
            isFloating : Bool = true,
            bannerID   : String? = nil,
            dismissID  : String? = nil,
            hints      : [BluetoothNoticeConnectionHint] = [hint],
            at date    : Date = now
        ) -> Bool {
            let snapshot = BluetoothNoticeSnapshot(
                ownerBundleID          : bundleID,
                texts                  : texts,
                isModal                : isModal,
                hasInteractiveControls : hasControls,
                closeButtonCount       : closeCount,
                isComplete             : isComplete,
                isFloatingWindow       : isFloating,
                width                  : width,
                height                 : 120,
                bannerIdentifier       : bannerID,
                dismissButtonIdentifier: dismissID
            )

            // Italian system labels ("Connesse", "Connesso"): loadConnectionLabels reads every localization.
            return BluetoothNoticeMatchPolicy.matchingDevice(
                in             : snapshot,
                hints          : hints,
                connectedLabels: ["Connected", "Connesse", "Connesso"],
                now            : date
            ) != nil
        }

        precondition(
            accepts(["Studio Buds", "Connected", "82%"]),
            "A recent matching connection must be accepted."
        )
        precondition(
            accepts(["Studio Buds", "Connesse"]),
            "An OS-sourced localized connection label must be accepted."
        )
        precondition(
            !accepts(["Studio Buds Pro", "Connected"]),
            "Device names must match exactly."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], hints: []),
            "A real recent connection event is required."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], at: Date(timeIntervalSince1970: 106)),
            "Hints expire at their deadline."
        )
        precondition(
            !accepts(["Studio Buds", "Connected", "Pair"]),
            "Pairing content must remain visible."
        )
        precondition(
            !accepts(["Studio Buds", "Connected", "123456"]),
            "A numeric passkey must not be mistaken for battery content."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], isModal: true),
            "Modal prompts must remain visible."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], hasControls: true),
            "Interactive controls make a candidate unsafe to dismiss."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], closeCount: 2),
            "Ambiguous close buttons must be rejected."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], isComplete: false),
            "Incomplete traversal must fail closed."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], bundleID: "com.apple.notificationcenterui"),
            "Notification Center must never be a dismissal target."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], width: 700),
            "Large settings windows must remain visible."
        )

        let systemBannerID  = "smart-routing-system-banner"
        let systemDismissID = "com.apple.controlcenter.dismiss"
        precondition(
            accepts(
                ["Studio Buds", "Connected", "82%"],
                bundleID  : "com.apple.MenuBarAgent",
                isFloating: false,
                bannerID  : systemBannerID,
                dismissID : systemDismissID
            ),
            "The identified Smart Routing subtree can be dismissed inside a shared host window."
        )
        precondition(
            accepts(
                ["Studio Buds", "Connected"],
                isFloating: false,
                bannerID  : systemBannerID,
                dismissID : systemDismissID
            ),
            "Control Center may directly expose the same identified SystemBannerUI subtree."
        )
        precondition(
            !accepts(["Studio Buds", "Connected"], bundleID: "com.apple.MenuBarAgent"),
            "The shared MenuBarAgent window itself must never be dismissed."
        )

        for wrongID in [
            nil,
            "volume-system-banner",
            "listening-mode-system-banner",
            "smart-routing-system-banner-extra"
        ] {
            precondition(
                !accepts(
                    ["Studio Buds", "Connected"],
                    bundleID  : "com.apple.MenuBarAgent",
                    isFloating: false,
                    bannerID  : wrongID,
                    dismissID : systemDismissID
                ),
                "Only the exact Smart Routing identifier qualifies."
            )
        }

        for wrongID in [nil, "AXCloseButton", "close", "com.apple.controlcenter.dismiss-extra"] {
            precondition(
                !accepts(
                    ["Studio Buds", "Connected"],
                    bundleID  : "com.apple.MenuBarAgent",
                    isFloating: false,
                    bannerID  : systemBannerID,
                    dismissID : wrongID
                ),
                "Only the matching subtree dismiss action qualifies; never the host close button."
            )
        }

        for extraText in ["Moved to iPhone", "Connect", "Pair", "123456"] {
            precondition(
                !accepts(
                    ["Studio Buds", "Connected", extraText],
                    bundleID  : "com.apple.MenuBarAgent",
                    isFloating: false,
                    bannerID  : systemBannerID,
                    dismissID : systemDismissID
                ),
                "A reverse-route or pairing prompt must remain visible."
            )
        }

        precondition(
            !accepts(
                ["Studio Buds", "Moved to iPhone"],
                bundleID  : "com.apple.MenuBarAgent",
                isFloating: false,
                bannerID  : systemBannerID,
                dismissID : systemDismissID
            ),
            "A Smart Routing identifier alone does not establish a connected event."
        )
        precondition(
            !accepts(
                ["Studio Buds", "Connected"],
                hasControls: true,
                bundleID   : "com.apple.MenuBarAgent",
                isFloating : false,
                bannerID   : systemBannerID,
                dismissID  : systemDismissID
            ),
            "Other interactive controls forbid subtree dismissal."
        )
        precondition(
            !accepts(
                ["Studio Buds", "Connected"],
                isComplete: false,
                bundleID  : "com.apple.MenuBarAgent",
                isFloating: false,
                bannerID  : systemBannerID,
                dismissID : systemDismissID
            ),
            "An incomplete identified subtree must be rejected."
        )
        precondition(
            !accepts(
                ["Studio Buds", "Connected"],
                bundleID  : "com.apple.MenuBarAgent",
                isFloating: false,
                bannerID  : systemBannerID,
                dismissID : systemDismissID,
                hints     : []
            ),
            "The identified subtree still requires a real recent connection hint."
        )
        precondition(
            !accepts(
                ["Studio Buds", "Connected"],
                bundleID  : "com.apple.notificationcenterui",
                isFloating: false,
                bannerID  : systemBannerID,
                dismissID : systemDismissID
            ),
            "Identifiers cannot authorize another owner."
        )

        print("33 Bluetooth notice policy checks passed")
    }
}

#endif
