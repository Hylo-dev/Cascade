//
//  CascadeServices.swift
//  Cascade
//

import AppKit
import CascadeContracts
import CascadeKit
import CascadePlugins
import CascadeRuntime
import Observation

/// CascadeServices owns integration lifetimes independently of the notch views.
/// Each source feeds typed events into the public engine boundary. Disabling a
/// source finishes its stream and cancels consumption; no UI owns a monitor.
@MainActor
@Observable
final class CascadeServices {

    private(set) var displayDescriptors: [NotchDisplayDescriptor] = []

    var displayPreferences: DisplayPresentationPreferences {
        get {
            _ = displayPreferencesRevision
            return displayPreferencesStore.preferences
        }
        set {
            guard displayPreferencesStore.preferences != newValue else { return }

            displayPreferencesStore.preferences = newValue
            displayPreferencesRevision &+= 1
            notch.setDisplayPreferences(newValue)
        }
    }

    func canCalibrateDisplay(from origin: AuxiliaryInvocationOrigin) -> Bool {
        guard let displayID = invocationDisplayID(for: origin) else { return false }

        return displayDescriptors.first(where: { $0.runtimeID == displayID })?.hasHardwareNotch == true
    }

    var spotlightEnabled: Bool {
        didSet {
            preferences.set(spotlightEnabled, forKey: "spotlightEnabled")
            if isRunning { updateSpotlight() }
        }
    }

    var spotlightStatus: String { spotlight.status }

    func previewSpotlightDroplet(from origin: AuxiliaryInvocationOrigin) {
        guard let anchor = spotlightAnchor(on: invocationDisplayID(for: origin)) else { return }

        Task { @MainActor in spotlight.preview(at: anchor) }
    }

    func openSpotlight() {
        Task { @MainActor in spotlight.open() }
    }

    var hapticsEnabled: Bool {
        didSet {
            preferences.set(hapticsEnabled, forKey: "hapticsEnabled")
            notch.setHapticsEnabled(hapticsEnabled)
        }
    }

    var sensitiveContentVisible: Bool {
        didSet {
            preferences.set(sensitiveContentVisible, forKey: "sensitiveContentVisible")
            notch.setSensitiveContentVisible(sensitiveContentVisible)
        }
    }

    var bluetoothEnabled: Bool {
        didSet {
            preferences.set(bluetoothEnabled, forKey: "bluetoothEnabled")
            if isRunning { updateBluetoothMonitoring() }
        }
    }

    var nativeReplacementEnabled: Bool {
        didSet {
            preferences.set(nativeReplacementEnabled, forKey: "nativeReplacementEnabled")
            refreshNativeReplacement()
        }
    }

    var volumeEnabled: Bool {
        didSet {
            preferences.set(volumeEnabled, forKey: "volumeEnabled")
            plugins.setEnabled(volumeEnabled, for: VolumePlugin.id)
        }
    }

    var chargingEnabled: Bool {
        didSet {
            preferences.set(chargingEnabled, forKey: "chargingEnabled")
            plugins.setEnabled(chargingEnabled, for: ChargingPlugin.id)
        }
    }

    private(set) var volumeStatus: VolumeMonitoringStatus = .stopped

    var musicEnabled: Bool {
        didSet {
            preferences.set(musicEnabled, forKey: "musicEnabled")
            if isRunning { updateMusicMonitoring() }
        }
    }

    var audioVisualizerEnabled: Bool {
        didSet {
            preferences.set(audioVisualizerEnabled, forKey: "audioVisualizerEnabled")
            mediaActivity?.setAudioEnabled(audioVisualizerEnabled)
        }
    }

    var musicStatus: NowPlayingProviderStatus { mediaProvider.status }

    var audioSpectrumStatus: AudioSpectrumStatus {
        audioSpectrum.status == .stopped ? startupAudioStatus : audioSpectrum.status
    }

    func requestMusicAccess() {
        Task { await mediaProvider.requestAccess() }
    }

    func retryAudioCapture() {
        startupAudioStatus = .stopped
        mediaActivity?.retryAudioCapture()
    }

    func openAudioCaptureSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    var suppressionStatus: BluetoothNoticeSuppressionStatus { suppressor.status }
    var bluetoothStatus  : BluetoothMonitoringStatus { bluetooth.status }

    @ObservationIgnored
    private let notch              : NotchEngine
    @ObservationIgnored
    private let plugins            : PluginSystem
    @ObservationIgnored
    private let fileShelfGovernor  : ResourceGovernor
    @ObservationIgnored
    private let fileShelfController: FileShelfController
    @ObservationIgnored
    private var settings           : (any CascadeSettingsPresenting)?
    @ObservationIgnored
    private let spotlight          : SpotlightCoordinator

    @ObservationIgnored
    private let bluetooth    : any BluetoothMonitoring = IOBluetoothConnectionMonitor()
    @ObservationIgnored
    private let suppressor    = AccessibilityBluetoothNoticeSuppressor()
    @ObservationIgnored
    private let volumeSource = VolumePluginSource(monitor: CoreAudioVolumeMonitor())
    @ObservationIgnored
    private let network      : any NetworkMonitoring = NetworkConnectionMonitor()
    @ObservationIgnored
    private let mediaProvider = SystemNowPlayingProvider()
    @ObservationIgnored
    private let audioSpectrum = CoreAudioSpectrumMonitor()

    @ObservationIgnored
    private let preferences            : UserDefaults
    @ObservationIgnored
    private let displayPreferencesStore: DisplayPresentationPreferencesStore
    @ObservationIgnored
    private var settingsAnchorDisplayID: CGDirectDisplayID?

    private var displayPreferencesRevision: UInt64 = 0

    @ObservationIgnored
    private var bluetoothTask          : Task<Void, Never>?
    @ObservationIgnored
    private var bluetoothEventIDs      : [String: UInt64] = [:]
    @ObservationIgnored
    private var mediaTask              : Task<Void, Never>?
    @ObservationIgnored
    private var networkTask            : Task<Void, Never>?
    @ObservationIgnored
    private var networkBorderResetTask : Task<Void, Never>?
    @ObservationIgnored
    private var mediaActivity          : MediaLiveActivity?
    @ObservationIgnored
    private var startupPermissionTask  : Task<Void, Never>?
    @ObservationIgnored
    private var fileShelfStartTask     : Task<Void, Never>?
    @ObservationIgnored
    private var fileShelfNoticeRevision: UInt64 = 0

    @ObservationIgnored
    private let audioPermissionRequester = AudioCapturePermissionRequester()

    private var startupAudioStatus: AudioSpectrumStatus = .stopped

    @ObservationIgnored
    private var isRunning = false

    init(preferences: UserDefaults = .standard) {
        let displayPreferencesStore = DisplayPresentationPreferencesStore(defaults: preferences)
        let notch = NotchEngine(
            configuration     : .default,
            displayPreferences: displayPreferencesStore.preferences
        )
        self.notch                   = notch
        plugins                      = PluginSystem(host: notch, sources: [PluginVolumeState.source: volumeSource])
        self.displayPreferencesStore = displayPreferencesStore

        let fileShelfGovernor = ResourceGovernor()
        self.fileShelfGovernor = fileShelfGovernor
        do {
            let directory = try Self.makeFileShelfDirectory()
            let host      = try FileWorkspaceHost(directory: directory, governor: fileShelfGovernor)
            fileShelfController = FileShelfController(
                host             : host,
                preferenceChanged: { _ in }
            )
        } catch {
            fileShelfController = FileShelfController(
                startupError     : error,
                preferenceChanged: { _ in }
            )
        }

        spotlight = SpotlightCoordinator(
            anchor             : { [weak notch] in
                guard let notch,
                      let displayID = notch.auxiliaryDisplayID,
                      let restingBounds = notch.restingFrame,
                      let screen = NSScreen.screens.first(where: {
                          $0.cascadeRuntimeDisplayID == displayID
                      })
                else { return nil }

                return SpotlightDisplayAnchor(
                    displayID    : displayID,
                    screen       : screen,
                    restingBounds: restingBounds
                )
            },
            reservePresentation: { [weak notch] anchor, ready in
                notch?.reserveExternalSurface(on: anchor.displayID, ready: ready)
            },
            releasePresentation: { [weak notch] in
                notch?.releaseExternalSurface()
            }
        )

        self.preferences         = preferences
        spotlightEnabled         = preferences.object(forKey: "spotlightEnabled") as? Bool ?? true
        hapticsEnabled           = preferences.object(forKey: "hapticsEnabled") as? Bool ?? true
        sensitiveContentVisible  = preferences.object(forKey: "sensitiveContentVisible") as? Bool ?? false
        bluetoothEnabled         = preferences.object(forKey: "bluetoothEnabled") as? Bool ?? true
        nativeReplacementEnabled = preferences.object(forKey: "nativeReplacementEnabled") as? Bool ?? true
        volumeEnabled            = preferences.object(forKey: "volumeEnabled") as? Bool ?? true
        chargingEnabled          = preferences.object(forKey: "chargingEnabled") as? Bool ?? true
        musicEnabled             = preferences.object(forKey: "musicEnabled") as? Bool ?? true
        audioVisualizerEnabled   = preferences.object(forKey: "audioVisualizerEnabled") as? Bool ?? true

        settings = CascadeSettingsWindowController(
            onFocusChanged       : { [weak notch] isFocused in
                notch?.setSettingsFocused(isFocused)
            },
            onPresentationChanged: { [weak self, weak notch] isPresented in
                notch?.setSettingsPresented(isPresented)
                if !isPresented { self?.settingsAnchorDisplayID = nil }
            }
        )

        volumeSource.statusHandler = { [weak self] status in
            self?.volumeStatus = status
        }

        notch.onSettingsRequested = { [weak self] in
            self?.showSettings(reanchorToCurrentOwner: false)
        }

        notch.onExpandedFrameChanged = { [weak self, weak notch] frame in
            guard let self,
                  self.settingsAnchorDisplayID == nil
                    || notch?.expandedDisplayID == self.settingsAnchorDisplayID
            else { return }

            self.settings?.updateNotchFrame(frame)
        }

        notch.onDisplaysChanged = { [weak self] displays in
            guard let self else { return }

            self.displayDescriptors = displays
            if let anchor = self.settingsAnchorDisplayID,
               !displays.contains(where: { $0.runtimeID == anchor }) {
                self.settings?.close()
            }
            self.spotlight.displaysDidChange(Set(displays.map(\.runtimeID)))
        }

        notch.onScreenLocked = { [weak self] in
            self?.spotlight.screenLocked()
        }

        let fileShelfController = self.fileShelfController
        fileShelfController.setContentChanged { [weak fileShelfController, weak notch] prefersDefault in
            guard let fileShelfController else { return }

            notch?.setContextualPage(fileShelfController, prefersDefault: prefersDefault)
        }
        notch.setContextualPage(fileShelfController, prefersDefault: false)
        notch.configureFileDrop(
            onHover      : { [weak fileShelfController] urls in
                fileShelfController?.showHover(urls)
            },
            onDrop       : { [weak fileShelfController] urls in
                fileShelfController?.acceptDrop(urls) ?? false
            },
            onUnsupported: { [weak self, weak fileShelfController] in
                fileShelfController?.showUnsupportedDrop()
                guard let self else { return }

                self.fileShelfNoticeRevision &+= 1
                self.notch.showNotice(
                    FileShelfUnsupportedNotice(revision: self.fileShelfNoticeRevision)
                )
            }
        )
    }

    /// openSettings uses the expanded target before presentation, even when
    /// invoked from the menu while the notch is still compact.
    func openSettings() {
        showSettings(reanchorToCurrentOwner: true)
    }

    private func showSettings(reanchorToCurrentOwner: Bool) {
        guard isRunning else { return }

        notch.setSettingsPresented(
            true,
            reanchorToCurrentOwner: reanchorToCurrentOwner
        )
        notch.setSettingsFocused(true)
        guard let displayID = notch.auxiliaryDisplayID, let frame = notch.expandedFrame else {
            notch.setSettingsFocused(false)
            notch.setSettingsPresented(false)
            return
        }

        settingsAnchorDisplayID = displayID
        refreshNativeReplacement()
        settings?.show(services: self, notchFrame: frame)
    }

    func start() {
        guard !isRunning else { return }

        isRunning = true
        plugins.setEnabled(chargingEnabled, for: ChargingPlugin.id)
        plugins.setEnabled(volumeEnabled, for: VolumePlugin.id)
        plugins.start()
        notch.setHapticsEnabled(hapticsEnabled)
        notch.setSensitiveContentVisible(sensitiveContentVisible)
        fileShelfStartTask = Task { [weak fileShelfController] in
            await fileShelfController?.start()
        }

        notch.start()
        updateSpotlight()
        startNetworkMonitoring()
        updateBluetoothMonitoring()
        updateMusicMonitoring()
        requestStartupPermissions()

        #if DEBUG
        // Keep the production panel expanded for compositor inspection without
        // synthesizing global pointer events or opening another window over it.
        if CommandLine.arguments.contains("--inspect-expanded-notch") {
            notch.setSettingsFocused(true)
        }
        #endif
    }

    /// requestStartupPermissions starts the native consent flows once per app
    /// launch, independent of menu presentation or an active music session.
    private func requestStartupPermissions() {
        startupPermissionTask?.cancel()
        startupPermissionTask = Task { [weak self] in
            guard let self, self.isRunning, !Task.isCancelled else { return }

            let audioConsentKey = "startupAudioCaptureRequested"
            if self.musicEnabled && self.audioVisualizerEnabled
                && !self.preferences.bool(forKey: audioConsentKey) {
                let result = await self.audioPermissionRequester.requestAccess()
                guard self.isRunning, !Task.isCancelled else { return }

                // Once is enough. Core Audio has no public preflight and, without
                // consent, a tap still starts and delivers silence, so repeating
                // the full tap/aggregate/IO probe on every launch verified nothing.
                // A failed setup is retried next launch; later denials surface
                // from the real capture when music plays.
                if result == .capturing {
                    self.preferences.set(true, forKey: audioConsentKey)
                }
                self.startupAudioStatus = result == .capturing ? .stopped : result
                self.mediaActivity?.retryAudioCapture()
            }

            guard self.isRunning, !Task.isCancelled else { return }

            // Volume and native Bluetooth replacement use the same AX grant.
            if self.volumeEnabled {
                self.volumeSource.monitor.requestAccess()
            } else if self.bluetoothEnabled && self.nativeReplacementEnabled {
                self.suppressor.requestAccess()
            }

            if self.musicEnabled {
                await self.mediaProvider.requestAccess(includeInstalledPlayers: true)
            }
        }
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        settings?.close()
        spotlight.stop()

        startupPermissionTask?.cancel()
        startupPermissionTask = nil
        fileShelfStartTask?.cancel()
        fileShelfStartTask = nil
        fileShelfController.stop()
        startupAudioStatus = .stopped

        networkTask?.cancel()
        networkTask = nil
        networkBorderResetTask?.cancel()
        networkBorderResetTask = nil
        network.stop()

        notch.setBorderAppearance(.neutral)

        bluetoothTask?.cancel()
        bluetoothTask = nil
        bluetoothEventIDs.removeAll()
        bluetooth.stop()
        suppressor.stop()

        mediaTask?.cancel()
        mediaTask = nil
        mediaProvider.stop()
        if let mediaActivity { notch.endActivity(id: mediaActivity.id) }
        mediaActivity = nil

        notch.stop()
    }

    private static func makeFileShelfDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for           : .applicationSupportDirectory,
            in            : .userDomainMask,
            appropriateFor: nil,
            create        : true
        )
        let directory = applicationSupport
            .appendingPathComponent("Cascade", isDirectory: true)
            .appendingPathComponent("FileShelf", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        return directory
    }

    /// refreshNativeReplacement is called when the menu opens, allowing a newly
    /// granted AX permission to take effect without polling or restarting macOS.
    func refreshNativeReplacement() {
        if spotlightEnabled { spotlight.refresh() }
        refreshVolumePermissions()

        guard isRunning,
              bluetoothEnabled,
              bluetooth.status == .monitoring,
              nativeReplacementEnabled
        else {
            suppressor.stop()
            return
        }

        suppressor.start()
    }

    func requestAccessibility() {
        suppressor.requestAccess()
    }

    private func updateSpotlight() {
        if spotlightEnabled { spotlight.start() }
        else { spotlight.stop() }
    }

    /// beginSizeCalibration opens the notch's reversible alignment tool.
    func beginSizeCalibration(from origin: AuxiliaryInvocationOrigin) {
        guard let displayID = invocationDisplayID(for: origin),
              canCalibrateDisplay(from: origin)
        else { return }

        notch.beginSizeCalibration(on: displayID)
    }

    private func invocationDisplayID(for origin: AuxiliaryInvocationOrigin) -> CGDirectDisplayID? {
        origin.resolve(
            settingsDisplayID: settingsAnchorDisplayID,
            activeDisplayID  : notch.auxiliaryDisplayID
        )
    }

    /// spotlightAnchor resolves exact engine geometry for the requested
    /// contextual display, or the current owner for a global invocation.
    private func spotlightAnchor(on requestedDisplayID: CGDirectDisplayID?) -> SpotlightDisplayAnchor? {
        guard let displayID = requestedDisplayID ?? notch.auxiliaryDisplayID,
              let restingBounds = notch.restingFrame(on: displayID),
              let screen = NSScreen.screens.first(where: {
                  $0.cascadeRuntimeDisplayID == displayID
              })
        else { return nil }

        return SpotlightDisplayAnchor(
            displayID    : displayID,
            screen       : screen,
            restingBounds: restingBounds
        )
    }

    /// setDisplayStyle persists stable identities and keeps unresolved display
    /// choices scoped to the current runtime connection.
    func setDisplayStyle(
        _ style    : ExternalNotchStyle,
        for display: NotchDisplayDescriptor
    ) {
        guard !display.hasHardwareNotch else { return }
        guard let identity = display.identity else {
            notch.setTransientDisplayStyle(style, for: display.runtimeID)
            return
        }

        var styles = displayPreferences.styles
        styles[identity] = style
        displayPreferences = DisplayPresentationPreferences(
            activityMode: displayPreferences.activityMode,
            styles      : styles
        )
    }

    /// setActivityDisplayMode writes the single persisted routing payload while
    /// preserving every per-display style selection.
    func setActivityDisplayMode(_ mode: LiveActivityDisplayMode) {
        displayPreferences = DisplayPresentationPreferences(
            activityMode: mode,
            styles      : displayPreferences.styles
        )
    }

    func refreshVolumePermissions() {
        guard isRunning, volumeEnabled else { return }

        volumeSource.monitor.refreshPermissions()
    }

    func requestVolumeAccessibility() {
        volumeSource.monitor.requestAccess()
    }

    /// previewVolume never adjusts hardware or installs an input tap. The volume plugin draws the
    /// preview through its own preview action.
    func previewVolume() {
        plugins.invoke(VolumePlugin.preview, feature: VolumePlugin.feature, of: VolumePlugin.id)
    }

    /// previewBluetooth is explicitly synthetic and never arms the native
    /// suppressor: a demo must not dismiss any real system notification.
    func previewBluetooth() {
        let event = BluetoothConnectionEvent(
            deviceID   : "demo-headphones",
            name       : String(localized: "AirPods · Preview"),
            symbolName : "airpodspro",
            isConnected: true,
            battery    : BluetoothBatterySnapshot(
                left     : 72,
                right    : 68,
                caseLevel: 81
            ),
            model      : .airPodsPro,
            productID  : 0x200E
        )
        let activity = BluetoothConnectionActivity(event: event)
        notch.showNotice(activity)
    }

    /// previewCharging changes presentation only; it never changes macOS energy settings. The
    /// charging plugin draws the preview through its own preview action.
    func previewCharging(lowPower: Bool) {
        plugins.invoke(ChargingPlugin.preview, value: .bool(lowPower), feature: ChargingPlugin.feature, of: ChargingPlugin.id)
    }

    private func updateBluetoothMonitoring() {
        bluetoothTask?.cancel()
        bluetoothTask = nil
        bluetoothEventIDs.removeAll()
        bluetooth.stop()
        notch.dismissActivities(from: "cascade.bluetooth")
        guard bluetoothEnabled else {
            suppressor.stop()
            return
        }

        let stream = bluetooth.start()
        refreshNativeReplacement()
        bluetoothTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self, self.isRunning else { return }

                let activity = BluetoothConnectionActivity(event: event)
                if event.revision == 0 {
                    self.bluetoothEventIDs[event.deviceID] = event.eventID
                    if event.isConnected, self.nativeReplacementEnabled {
                        // A real route/connection also refreshes AX trust and
                        // banner-host identity without depending on menu mount.
                        self.suppressor.start()
                        self.suppressor.expectConnection(deviceName: event.name)
                    }
                    self.notch.showNotice(activity)
                } else if self.bluetoothEventIDs[event.deviceID] == event.eventID {
                    // Battery/model enrichment cannot replay an old connection,
                    // extend its deadline or rearm native-banner suppression.
                    self.notch.updateNotice(activity)
                }
            }
        }
    }

    /// startNetworkMonitoring keeps the ordinary rim neutral. An actual new
    /// connection briefly signals green; the initial snapshot and duplicate
    /// updates never recolor a notch merely because the Mac is already online.
    private func startNetworkMonitoring() {
        let stream = network.start()
        networkTask = Task { [weak self] in
            var previousConnection: Bool?
            for await isConnected in stream {
                guard !Task.isCancelled, let self, self.isRunning else { return }

                let previous = previousConnection
                previousConnection = isConnected
                guard let previous, previous != isConnected else { continue }

                self.networkBorderResetTask?.cancel()
                self.networkBorderResetTask = nil
                self.notch.setBorderAppearance(isConnected ? .connected : .neutral)
                guard isConnected else { continue }

                self.networkBorderResetTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(4))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, let self, self.isRunning else { return }

                    self.notch.setBorderAppearance(.neutral)
                    self.networkBorderResetTask = nil
                }
            }
        }
    }

    private func updateMusicMonitoring() {
        mediaTask?.cancel()
        mediaTask = nil
        mediaProvider.stop()
        notch.setExpandedFallback(nil)
        if let mediaActivity { notch.endActivity(id: mediaActivity.id) }
        mediaActivity = nil
        guard isRunning, musicEnabled else { return }

        let stream = mediaProvider.start()
        mediaTask = Task { [weak self] in
            for await snapshot in stream {
                guard !Task.isCancelled, let self, self.isRunning else { return }
                guard let snapshot else {
                    guard let activity = self.mediaActivity else { continue }

                    // A stopped player keeps its last cover as the widget; one
                    // that has quit leaves the notch as it was before it played.
                    if Self.isRunning(activity.sourceBundleIdentifier) {
                        activity.markPlaybackStopped()
                        self.notch.setExpandedFallback(activity)
                    } else {
                        self.notch.setExpandedFallback(nil)
                        self.mediaActivity = nil
                    }
                    self.notch.endActivity(id: activity.id)
                    continue
                }

                if snapshot.isPlaying {
                    // The live monitor now owns permission/error reporting.
                    self.startupAudioStatus = .stopped
                }

                if let activity = self.mediaActivity {
                    activity.update(snapshot)
                    self.notch.setExpandedFallback(activity)
                    if snapshot.isPlaying { self.notch.present(activity) }
                    else { self.notch.endActivity(id: activity.id) }
                } else {
                    let activity = MediaLiveActivity(
                        snapshot    : snapshot,
                        spectrum    : self.audioSpectrum,
                        audioEnabled: self.audioVisualizerEnabled,
                        send        : { [weak self] command, displayedSnapshot in
                            guard let self, self.musicEnabled else { return }

                            try await self.mediaProvider.send(command, matching: displayedSnapshot)
                        }
                    )
                    self.mediaActivity = activity
                    self.notch.setExpandedFallback(activity)
                    if snapshot.isPlaying { self.notch.present(activity) }
                }
            }
        }
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }
}
