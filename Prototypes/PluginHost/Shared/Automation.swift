//
//  Automation.swift
//  PluginHost
//

import CoreServices
import Foundation

/// automationStatus is AEDeterminePermissionToAutomateTarget for one bundle identifier.
func automationStatus(
    bundleIdentifier: String,
    ask             : Bool
) -> Int32 {
    var target = AEAddressDesc()
    let bytes  = Array(bundleIdentifier.utf8)
    let made   = bytes.withUnsafeBytes { buffer in
        AECreateDesc(typeApplicationBundleID, buffer.baseAddress, buffer.count, &target)
    }
    guard made == noErr else { return Int32(made) }

    defer { AEDisposeDesc(&target) }

    return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
}

/// applicationName sends one read-only Apple Event, `get name`, to a running application. It
/// never launches the target and never changes its state.
func applicationName(bundleIdentifier: String) -> (Int32, String) {
    let target    = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
    let event     = NSAppleEventDescriptor(
        eventClass      : AEEventClass(kAECoreSuite),
        eventID         : AEEventID(kAEGetData),
        targetDescriptor: target,
        returnID        : AEReturnID(kAutoGenerateReturnID),
        transactionID   : AETransactionID(kAnyTransactionID)
    )
    let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))!
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: OSType(typeProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
    specifier.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: OSType(pName)), forKeyword: AEKeyword(keyAEKeyData))
    specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
    event.setParam(specifier, forKeyword: AEKeyword(keyDirectObject))

    do {
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 5)

        return (0, reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "")
    } catch {
        return (Int32((error as NSError).code), "")
    }
}
