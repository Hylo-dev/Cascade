//
//  AddonPresentationSink.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

@MainActor
protocol AddonPresentationSink: AnyObject {

    func register(_ widget: any NotchWidget)
    func unregisterWidget(id: WidgetIdentifier)
    func present(_ activity: any NotchLiveActivity)
    func showNotice(_ notice: any NotchTransientNotice)
    func updateNotice(_ notice: any NotchTransientNotice)
    func dismissActivity(id: String)
    func dismissActivities(from sourceID: String)
    func captureOptionsOrigin(publicationID: PublicationID, observedRevision: UInt64) -> AddonOptionsOrigin?
    func presentOptions(page: any NotchContextualPage, leaseID: UUID, origin: AddonOptionsOrigin, onDismiss: @escaping @MainActor () -> Void) -> Bool
    func dismissOptions(leaseID: UUID)
}

extension AddonPresentationSink {

    func captureOptionsOrigin(publicationID: PublicationID, observedRevision: UInt64) -> AddonOptionsOrigin? { nil }
    func presentOptions(page: any NotchContextualPage, leaseID: UUID, origin: AddonOptionsOrigin, onDismiss: @escaping @MainActor () -> Void) -> Bool { false }
    func dismissOptions(leaseID: UUID) {}
}
