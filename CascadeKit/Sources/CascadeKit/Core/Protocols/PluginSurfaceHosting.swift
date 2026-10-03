//
//  PluginSurfaceHosting.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginSurfaceHosting is the part of the notch plugin surfaces need: placing a widget on the
/// grid and taking it off, showing a notice, enriching it and dismissing it. The notch engine provides it;
/// tests record it.
@MainActor
public protocol PluginSurfaceHosting: AnyObject {

    func register(_ widget: NotchWidget)

    func unregisterWidget(id: WidgetIdentifier)

    func present(_ activity: any NotchLiveActivity)

    func showNotice(_ notice: any NotchTransientNotice)

    func updateNotice(_ notice: any NotchTransientNotice)

    func dismissActivity(id: String)

    func capturePluginOptionsOrigin(widgetID: WidgetIdentifier, publicationID: PublicationID, observedRevision: UInt64) -> AddonOptionsOrigin?
    func presentOptions(page: any NotchContextualPage, leaseID: UUID, origin: AddonOptionsOrigin, onDismiss: @escaping @MainActor () -> Void) -> Bool
    func dismissOptions(leaseID: UUID)
}

public extension PluginSurfaceHosting {

    func capturePluginOptionsOrigin(widgetID: WidgetIdentifier, publicationID: PublicationID, observedRevision: UInt64) -> AddonOptionsOrigin? { nil }
    func presentOptions(page: any NotchContextualPage, leaseID: UUID, origin: AddonOptionsOrigin, onDismiss: @escaping @MainActor () -> Void) -> Bool { false }
    func dismissOptions(leaseID: UUID) {}
}
