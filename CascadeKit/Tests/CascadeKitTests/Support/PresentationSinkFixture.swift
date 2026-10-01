//
//  PresentationSinkFixture.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import CascadeRuntime
import Foundation
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class PresentationSinkFixture: AddonPresentationSink {

    var registeredWidgets    : [any NotchWidget] = []
    var unregisteredWidgetIDs: [WidgetIdentifier] = []
    var presentedActivities  : [any NotchLiveActivity] = []
    var shownNotices         : [any NotchTransientNotice] = []
    var updatedNotices       : [any NotchTransientNotice] = []

    func register(_ widget: any NotchWidget) { registeredWidgets.append(widget) }

    func unregisterWidget(id: WidgetIdentifier) { unregisteredWidgetIDs.append(id) }

    func present(_ activity: any NotchLiveActivity) { presentedActivities.append(activity) }

    func showNotice(_ notice: any NotchTransientNotice) { shownNotices.append(notice) }

    func updateNotice(_ notice: any NotchTransientNotice) { updatedNotices.append(notice) }

    func dismissActivity(id: String) {}

    func dismissActivities(from sourceID: String) {}
}
