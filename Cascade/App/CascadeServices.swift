//
//  CascadeServices.swift
//  Cascade
//

import AppKit
import CascadeContracts
import CascadeKit
import CascadePluginEngine
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

    /// The Caffeinate settings forward to a mirror (see `CaffeinateSettingsMirror`): a write by
    /// the user sends the service a command, and a state the service published updates the
    /// mirror without sending one, so the options page and a refused display assertion show in
    /// Settings too.
    var caffeinateGlyph: CaffeinateGlyph {
        get { caffeinateSettings.glyph }
        set { caffeinateSettings.glyph = newValue }
    }

    var caffeinateKeepsDisplayAwake: Bool {
        get { caffeinateSettings.keepsDisplayAwake }
        set { caffeinateSettings.keepsDisplayAwake = newValue }
    }

    private(set) var caffeinateShortcut: CaffeinateShortcut?

    /// True when the system refused the shortcut the user chose, because another app owns it.
    /// The choice stays persisted so Settings shows what the user picked. It is only ever set by
    /// a registration that was attempted: while Caffeinate is not active nothing is registered,
    /// and nothing was refused.
    private(set) var caffeinateShortcutUnavailable = false

    /// setCaffeinateShortcutRecording frees the global combination while the recorder listens, so
    /// pressing the current shortcut records it instead of toggling Caffeinate, and registers the
    /// current one again when recording ends.
    func setCaffeinateShortcutRecording(_ isRecording: Bool) {
        isRecordingCaffeinateShortcut = isRecording

        if isRecording {
            caffeinateHotKey.register(nil)
        } else {
            registerCaffeinateShortcut()
        }
    }

    /// setCaffeinateShortcut persists the shortcut and registers it, `nil` meaning off. The
    /// preferences are written from the main actor: a single `UserDefaults` set, never on the
    /// service's queue, which only touches the other keys.
    func setCaffeinateShortcut(_ shortcut: CaffeinateShortcut?) {
        caffeinatePreferences.shortcut = shortcut
        caffeinateShortcut             = shortcut
        registerCaffeinateShortcut()
    }

    /// registerCaffeinateShortcut holds the global hot key only while it can do something: while
    /// Cascade runs and Caffeinate is active, and not while the recorder listens. Otherwise the
    /// combination is given back, so ⌃⌥⌘C is not taken from other apps for a plugin that is off.
    private func registerCaffeinateShortcut() {
        guard !isRecordingCaffeinateShortcut else { return }

        let wanted = isRunning && caffeinateSessionsAllowed ? caffeinateShortcut : nil

        caffeinateShortcutUnavailable = !caffeinateHotKey.register(wanted)
    }

    /// updateCaffeinatePermission follows the engine's status: a session may run while Caffeinate
    /// is active, whatever PluginHost does, and the service and the hot key hear only of a change.
    private func updateCaffeinatePermission(from status: PluginEngineStatus) {
        let allowed = CaffeinateCommand.sessionsAllowed(in: status.plugins)

        guard allowed != caffeinateSessionsAllowed else { return }

        caffeinateSessionsAllowed = allowed
        caffeinateService.setSessionsAllowed(allowed)
        registerCaffeinateShortcut()
    }

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
            plugins.setEnabled(bluetoothEnabled, for: BluetoothPlugin.id)
            guard !bluetoothEnabled else { return }

            bluetoothStatus = .stopped
            suppressor.stop()
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
            updateVolumeRouting()
        }
    }

    var audioEnabled: Bool {
        didSet {
            preferences.set(audioEnabled, forKey: "audioEnabled")
            plugins.setEnabled(audioEnabled, for: AudioPlugin.id)
            if audioEnabled && isRunning {
                systemAudio.start()
            } else {
                systemAudio.stop()
            }
            appAudio.setEnabled(audioEnabled && isRunning)
        }
    }

    var chargingEnabled: Bool {
        didSet {
            preferences.set(chargingEnabled, forKey: "chargingEnabled")
            plugins.setEnabled(chargingEnabled, for: ChargingPlugin.id)
        }
    }

    private(set) var volumeStatus: VolumeMonitoringStatus = .stopped

    /// audioHostStatus is the health of AudioHost, the process that steers each app's volume, for
    /// settings.
    private(set) var audioHostStatus: AudioHostStatus = .idle

    /// pluginStatus is each plugin's state and PluginHost's, for settings; nil until the engine
    /// has been composed.
    private(set) var pluginStatus: PluginEngineStatus?

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

    /// bluetoothStatus is what the Bluetooth plugin's source last said about monitoring, as its
    /// states reach the engine: monitoring once its baseline arrives, unavailable when IOBluetooth
    /// refused it, stopped while the alerts are off or Cascade is not running.
    private(set) var bluetoothStatus: BluetoothMonitoringStatus = .stopped

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
    private let caffeinateService    : CaffeinateService
    @ObservationIgnored
    private let caffeinatePreferences: UserDefaultsCaffeinatePreferences
    @ObservationIgnored
    private let caffeinateHotKey     : CaffeinateHotKey
    @ObservationIgnored
    private let caffeinateSettings   : CaffeinateSettingsMirror
    @ObservationIgnored
    private var caffeinateSessionsAllowed     = false
    @ObservationIgnored
    private var isRecordingCaffeinateShortcut = false

    @ObservationIgnored
    private let suppressor    = AccessibilityBluetoothNoticeSuppressor()
    @ObservationIgnored
    private let systemAudio  : SystemAudioService
    @ObservationIgnored
    private let appAudio     : AppAudioService
    @ObservationIgnored
    private var suppressorArming = BluetoothSuppressorArming()
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

        // The service touches NSWorkspace when it is created, which is why it is built here on
        // the main actor. It holds no assertion until the engine reports Caffeinate active and a
        // command reaches it.
        let caffeinatePreferences = UserDefaultsCaffeinatePreferences(defaults: preferences)
        let caffeinateService     = CaffeinateService(
            assertions : IOKitCaffeinateAssertions(),
            preferences: caffeinatePreferences,
            calendar   : { .autoupdatingCurrent }
        )
        self.caffeinatePreferences  = caffeinatePreferences
        self.caffeinateService      = caffeinateService
        caffeinateHotKey            = CaffeinateHotKey(
            onPress: { [caffeinateService] in caffeinateService.perform(.toggle) }
        )
        let caffeinateSettings      = CaffeinateSettingsMirror(
            glyph            : caffeinatePreferences.glyph,
            keepsDisplayAwake: caffeinatePreferences.keepsDisplayAwake,
            send             : { [caffeinateService] in caffeinateService.perform($0) }
        )
        self.caffeinateSettings     = caffeinateSettings
        caffeinateShortcut          = caffeinatePreferences.shortcut

        self.notch                   = notch
        let audioQueue  = DispatchQueue(label: "cascade.system-audio", qos: .utility)
        let audioOrigin = ContinuousClock.now
        let appAudio    = AppAudioService(
            connection: AudioHostClient(),
            store     : AudioIntentStore(defaults: preferences),
            queue     : DispatchQueue(label: "cascade.app-audio", qos: .utility),
            clock     : { audioOrigin.duration(to: .now) },
            isEnabled : false
        )
        let systemAudio = SystemAudioService(
            hardware: CoreAudioSystemHardware(queue: audioQueue),
            queue   : audioQueue,
            apps    : appAudio
        )
        self.appAudio                = appAudio
        self.systemAudio             = systemAudio
        plugins                      = PluginSystem(
            host             : notch,
            sources          : [
                PluginCaffeinateState.source: CaffeinatePluginSource(service: caffeinateService),
                PluginVolumeState.source    : volumeSource,
            ],
            services         : ["audio.system", "audio.apps"],
            componentServices: PluginComponentServices(audio: systemAudio.model)
        )
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
        audioEnabled             = preferences.object(forKey: "audioEnabled") as? Bool ?? true
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

        plugins.statusHandler = { [weak self] status in
            self?.pluginStatus = status
            self?.updateCaffeinatePermission(from: status)
            self?.updateVolumeRouting()
        }

        // Caffeinate's power assertion stays in Cascade: its widget's controls reach the service
        // only after the broker accepted them. The closure holds the service, not self, so there
        // is no cycle through the plugin system.
        plugins.actionHandler = { [caffeinateService] key, event in
            guard
                key.plugin == CaffeinateCommand.plugin,
                let command = CaffeinateCommand(event)
            else { return }

            caffeinateService.perform(command)
        }

        volumeSource.statusHandler = { [weak self] status in
            self?.volumeStatus = status
        }
        updateVolumeRouting()

        // The mixer's model draws what AudioHost reports and what became of AudioHost itself.
        // Both arrive on the main actor, from the service's single hop per delivery.
        let mixerModel = systemAudio.model
        appAudio.onSnapshot = { [weak mixerModel] snapshot in
            mixerModel?.receive(snapshot)
        }
        appAudio.onStatus = { [weak self, weak mixerModel] status in
            self?.audioHostStatus = status
            mixerModel?.receive(health: status.health)
        }

        // Every Bluetooth state reaches the suppressor as it reaches the engine, before the
        // engine keeps only the latest for the plugin, so no new connection is missed.
        plugins.observe(PluginBluetoothState.source) { @Sendable [weak self] event in
            guard let state = PluginBluetoothState(event) else { return }

            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.receiveBluetooth(state)
                    self?.systemAudio.receive(state)
                }
            }
        }

        // Every state the service publishes reaches Settings' mirror, whoever caused it: the
        // widget, the options page, the shortcut or a refused assertion.
        plugins.observe(PluginCaffeinateState.source) { @Sendable [caffeinateSettings] event in
            guard let state = PluginCaffeinateState(event) else { return }

            DispatchQueue.main.async {
                MainActor.assumeIsolated { caffeinateSettings.apply(state) }
            }
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
        plugins.setEnabled(bluetoothEnabled, for: BluetoothPlugin.id)
        plugins.setEnabled(chargingEnabled, for: ChargingPlugin.id)
        plugins.setEnabled(volumeEnabled, for: VolumePlugin.id)
        plugins.setEnabled(audioEnabled, for: AudioPlugin.id)
        if audioEnabled { systemAudio.start() }
        appAudio.setEnabled(audioEnabled)
        plugins.start()
        registerCaffeinateShortcut()
        notch.setHapticsEnabled(hapticsEnabled)
        notch.setSensitiveContentVisible(sensitiveContentVisible)
        fileShelfStartTask = Task { [weak fileShelfController] in
            await fileShelfController?.start()
        }

        notch.start()
        updateSpotlight()
        startNetworkMonitoring()
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

        appAudio.setEnabled(false)
        systemAudio.stop()
        systemAudio.restoreBeforeQuit()

        bluetoothStatus = .stopped
        suppressor.stop()

        mediaTask?.cancel()
        mediaTask = nil
        mediaProvider.stop()
        if let mediaActivity { notch.endActivity(id: mediaActivity.id) }
        mediaActivity = nil

        caffeinateHotKey.register(nil)

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
        updateNativeReplacement()
    }

    /// updateNativeReplacement watches for macOS's own Bluetooth banner only while Cascade shows
    /// its Bluetooth notices in its place.
    private func updateNativeReplacement() {
        guard isRunning,
              bluetoothEnabled,
              bluetoothStatus == .monitoring,
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

    /// routesVolumeKeys says whether the volume keys may replace the system HUD: only while the
    /// volume alerts are switched on and running, since they draw the replacement. The volume
    /// widget leases the same source, so the source may run while the alerts are off, quarantined
    /// or stopped after a hang, and macOS then keeps its own HUD. Before the engine reports any
    /// state the alerts count as running, so the tap is in place from the source's first start.
    static func routesVolumeKeys(
        alertsEnabled: Bool,
        alertsState  : PluginState?
    ) -> Bool {
        alertsEnabled && (alertsState ?? .active) == .active
    }

    private func updateVolumeRouting() {
        volumeSource.monitor.routesKeys = Self.routesVolumeKeys(
            alertsEnabled: volumeEnabled,
            alertsState  : pluginStatus?.plugins[VolumePlugin.id]
        )
    }

    /// reenablePlugin brings back a plugin stopped after a hang or quarantined.
    func reenablePlugin(_ plugin: PluginID) {
        plugins.reenable(plugin)
    }

    /// restartPluginHost tries PluginHost again after repeated crashes.
    func restartPluginHost() {
        plugins.restartHost()
    }

    /// restartAudioHost tries AudioHost again after repeated failures.
    func restartAudioHost() {
        appAudio.restart()
    }

    /// previewVolume never adjusts hardware or installs an input tap. The volume plugin draws the
    /// preview through its own preview action.
    func previewVolume() {
        plugins.invoke(VolumePlugin.preview, feature: VolumePlugin.feature, of: VolumePlugin.id)
    }

    /// previewBluetooth is explicitly synthetic and never arms the native suppressor: a demo must
    /// not dismiss any real system notification. The Bluetooth plugin draws the preview through
    /// its own preview action, which never passes through the source.
    func previewBluetooth() {
        plugins.invoke(BluetoothPlugin.preview, feature: BluetoothPlugin.feature, of: BluetoothPlugin.id)
    }

    /// previewCharging changes presentation only; it never changes macOS energy settings. The
    /// charging plugin draws the preview through its own preview action.
    func previewCharging(lowPower: Bool) {
        plugins.invoke(ChargingPlugin.preview, value: .bool(lowPower), feature: ChargingPlugin.feature, of: ChargingPlugin.id)
    }

    /// receiveBluetooth follows the Bluetooth source's states. Its availability is the menu's
    /// status, and a new connection, the moment macOS raises its own banner, arms the native
    /// banner's suppressor for that device. A battery or model reading of the same event, or the
    /// same state sent again with a new list of devices, never arms it again
    /// (`BluetoothSuppressorArming`).
    private func receiveBluetooth(_ state: PluginBluetoothState) {
        guard isRunning, bluetoothEnabled else { return }

        let status: BluetoothMonitoringStatus = state.isAvailable
            ? .monitoring
            : .unavailable("IOBluetooth connection notifications are unavailable.")
        if status != bluetoothStatus {
            bluetoothStatus = status
            updateNativeReplacement()
        }

        guard suppressorArming.arms(for: state), nativeReplacementEnabled else { return }

        // A real route or connection also refreshes AX trust and banner-host identity without
        // depending on the menu being open.
        suppressor.start()
        suppressor.expectConnection(deviceName: state.name)
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
