//
//  CascadeSettingsView.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// CascadeSettingsView uses the system sidebar, grouped forms and controls.
/// Filtering renders the actual settings in place, including cross-page results.
struct CascadeSettingsView: View {

    @Bindable
    var services: CascadeServices

    @State
    private var selection: CascadeSettingsPage? = .appearance
    @State
    private var query     = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var results: [CascadeSetting] {
        CascadeSetting.allCases.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationSplitView {

            List(selection: $selection) {

                ForEach(CascadeSettingsPage.allCases) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        Image(systemName: page.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(page.color, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 3)
                    .tag(page)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        } detail: {

            Group {

                if isSearching {
                    searchResults
                } else {
                    pageContent(selection ?? .appearance)
                }
            }
            .navigationTitle(isSearching ? String(localized: "Search Results") : (selection ?? .appearance).title)
            .frame(minWidth: 390)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, _ in query = "" }
    }

    private func pageContent(_ page: CascadeSettingsPage) -> some View {
        Form {

            switch page {
                case .appearance:
                    Section("Notch") {

                        settingRow(.size)

                        settingRow(.haptics)
                    }

                    Section("Displays") {

                        settingRow(.displayStyle)

                        settingRow(.activityDisplays)
                    }

                    Section("Privacy") { settingRow(.privacy) }

                case .dev:
                    Section {

                        ForEach(CascadeSetting.allCases.filter { $0.page == .dev }) { settingRow($0) }
                    } header: {
                        Text("Previews")
                    } footer: {
                        Text("Try the notch’s alerts and animations.")
                    }

                    Section("Application") {

                        LabeledContent("Version", value: appVersion)
                    }

                case .widget:
                    Section("Music") {

                        settingRow(.music)

                        settingRow(.visualizer)
                    }

                    Section("Alerts") {

                        settingRow(.bluetooth)

                        settingRow(.nativeBluetooth)

                        settingRow(.volume)

                        settingRow(.charging)
                    }

                    Section("Search") { settingRow(.spotlight) }

                    PluginStatusSection(services: services)

                    permissions
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Form {

                ForEach(CascadeSettingsPage.allCases) { page in
                    let matches = results.filter { $0.page == page }
                    if !matches.isEmpty {
                        Section(page.title) {

                            ForEach(matches) { settingRow($0) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func settingRow(_ setting: CascadeSetting) -> some View {
        switch setting {
            case .size:
                actionRow(setting, button: String(localized: "Adjust…")) {
                    services.beginSizeCalibration(from: .settings)
                }
                .disabled(!services.canCalibrateDisplay(from: .settings))

            case .haptics:
                toggleRow(setting, value: $services.hapticsEnabled)
            case .privacy:
                toggleRow(setting, value: $services.sensitiveContentVisible)
            case .displayStyle:
                displayStyleRows(setting)
            case .activityDisplays:
                activityDisplayRows(setting)
            case .music:
                toggleRow(setting, value: $services.musicEnabled)

            case .visualizer:
                toggleRow(setting, value: $services.audioVisualizerEnabled)
                    .disabled(!services.musicEnabled)

            case .bluetooth:
                toggleRow(setting, value: $services.bluetoothEnabled)

            case .nativeBluetooth:
                toggleRow(setting, value: $services.nativeReplacementEnabled)
                    .disabled(!services.bluetoothEnabled)

            case .volume:
                toggleRow(setting, value: $services.volumeEnabled)
            case .charging:
                toggleRow(setting, value: $services.chargingEnabled)
            case .spotlight:
                toggleRow(setting, value: $services.spotlightEnabled)
            case .volumePreview:
                actionRow(setting) { services.previewVolume() }
                    .disabled(!services.volumeEnabled)
            case .chargingPreview:
                actionRow(setting) { services.previewCharging(lowPower: false) }
                    .disabled(!services.chargingEnabled)
            case .lowPowerPreview:
                actionRow(setting) { services.previewCharging(lowPower: true) }
                    .disabled(!services.chargingEnabled)
            case .bluetoothPreview:
                actionRow(setting) { services.previewBluetooth() }
                    .disabled(!services.bluetoothEnabled)
            case .spotlightPreview:
                actionRow(setting) { services.previewSpotlightDroplet(from: .settings) }
        }
    }

    @ViewBuilder
    private func displayStyleRows(_ setting: CascadeSetting) -> some View {
        if services.displayDescriptors.isEmpty {
            rowLabel(setting)
        } else {
            ForEach(services.displayDescriptors, id: \.runtimeID) { display in
                LabeledContent {
                    if display.hasHardwareNotch {
                        Text("Hardware notch")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Style", selection: displayStyleBinding(for: display)) {
                            Text("Notch")
                                .tag(ExternalNotchStyle.notch)

                            Text("Dynamic Island")
                                .tag(ExternalNotchStyle.dynamicIsland)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {

                        Text(display.name)

                        if display.identity == nil {
                            Text("Temporary choice for this connection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(displayAccessibilityLabel(display))
                .accessibilityIdentifier("settings.displayStyle.\(display.runtimeID)")
            }
        }
    }

    @ViewBuilder
    private func activityDisplayRows(_ setting: CascadeSetting) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            rowLabel(setting)

            Picker("Show Live Activities", selection: activitySelectionBinding) {
                ForEach(ActivityDisplaySelection.allCases) { selection in
                    Text(selection.title)
                        .tag(selection)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.activityDisplays")

            if activitySelection == .fixedDisplay {
                Picker("Display", selection: fixedDisplayBinding) {
                    ForEach(activityDisplayChoices) { choice in
                        Text(choice.isConnected ? choice.name : String(localized: "\(choice.name) · disconnected"))
                            .tag(choice.identity)
                            .accessibilityLabel(choice.accessibilityLabel)
                    }
                }
                .accessibilityIdentifier("settings.activityDisplays.fixed")
            }

            Text("Focus follows the active window; if that isn’t available, it uses the pointer, then the main display. The Cascade shape stays on every display.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activitySelection: ActivityDisplaySelection {
        switch services.displayPreferences.activityMode {
            case .allDisplays: .allDisplays
            case .focusedDisplay: .focusedDisplay
            case .fixedDisplay: .fixedDisplay
        }
    }

    private var activitySelectionBinding: Binding<ActivityDisplaySelection> {
        Binding(
            get: { activitySelection },
            set: { selection in
                switch selection {
                    case .allDisplays:
                        services.setActivityDisplayMode(.allDisplays)
                    case .focusedDisplay:
                        services.setActivityDisplayMode(.focusedDisplay)

                    case .fixedDisplay:
                        if let identity = activityDisplayChoices.first?.identity {
                            services.setActivityDisplayMode(.fixedDisplay(identity))
                        }
                }
            }
        )
    }

    private var activityDisplayChoices: [DisplaySettingsModel.ActivityDisplayChoice] {
        let selected: DisplayIdentity?
        if case let .fixedDisplay(identity) = services.displayPreferences.activityMode {
            selected = identity
        } else {
            selected = nil
        }

        return DisplaySettingsModel.activityDisplayChoices(
            displays: services.displayDescriptors,
            selected: selected
        )
    }

    private var fixedDisplayBinding: Binding<DisplayIdentity> {
        Binding(
            get: {
                if case let .fixedDisplay(identity) = services.displayPreferences.activityMode {
                    return identity
                }

                return activityDisplayChoices.first?.identity ?? DisplayIdentity(rawValue: "")
            },
            set: { services.setActivityDisplayMode(.fixedDisplay($0)) }
        )
    }

    private func displayStyleBinding(for display: NotchDisplayDescriptor) -> Binding<ExternalNotchStyle> {
        Binding(
            get: { display.style },
            set: { services.setDisplayStyle($0, for: display) }
        )
    }

    private func displayAccessibilityLabel(_ display: NotchDisplayDescriptor) -> String {
        let identity = display.identity?.rawValue ?? String(localized: "session \(display.runtimeID)")
        return "\(display.name), \(identity)"
    }

    private func toggleRow(
        _ setting: CascadeSetting,
        value    : Binding<Bool>
    ) -> some View {
        Toggle(isOn: value) { rowLabel(setting) }
            .toggleStyle(.switch)
            .accessibilityLabel(setting.title)
            .accessibilityHint(setting.subtitle)
            .accessibilityIdentifier("settings.\(setting.rawValue)")
    }

    private func actionRow(
        _ setting: CascadeSetting,
        button   : String = String(localized: "Test"),
        action   : @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {

            rowLabel(setting)

            Spacer(minLength: 12)

            Button(button, action: action)
                .accessibilityLabel("\(button) \(setting.title)")
                .accessibilityIdentifier("settings.\(setting.rawValue)")
        }
    }

    private func rowLabel(_ setting: CascadeSetting) -> some View {
        VStack(alignment: .leading, spacing: 4) {

            Text(setting.title)

            Text(setting.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var permissions: some View {
        if services.musicEnabled {
            switch services.musicStatus {
                case .permissionRequired(let message), .unavailable(let message):
                    Section("Music Access") {

                        Text(message)
                            .foregroundStyle(.secondary)

                        Button("Allow Player Access…") { services.requestMusicAccess() }
                    }

                default:
                    EmptyView()
            }
        }

        if services.volumeEnabled, services.volumeStatus == .permissionRequired {
            Section("Accessibility") {

                Text("Allow Cascade to use the volume keys to show the alert in the notch.")
                    .foregroundStyle(.secondary)

                Button("Allow Accessibility…") { services.requestVolumeAccessibility() }
            }
        }

        if services.bluetoothEnabled,
           services.nativeReplacementEnabled,
           services.suppressionStatus == .permissionRequired {
            Section("macOS Bluetooth Alerts") {

                Button("Allow Accessibility…") { services.requestAccessibility() }
            }
        }

        if services.musicEnabled,
           services.audioVisualizerEnabled,
           services.audioSpectrumStatus == .permissionRequired {
            Section("System Audio") {

                Button("Allow System Audio…") { services.openAudioCaptureSettings() }

                Button("Check Permission Again") { services.retryAudioCapture() }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        return "\(version) (\(build))"
    }
}
