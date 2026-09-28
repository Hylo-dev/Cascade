//
//  AddonPresentationSink.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
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
}
