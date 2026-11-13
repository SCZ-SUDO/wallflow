import AppKit
import AVFoundation
import Combine

/// Owns the video player and one wallpaper window per display.
final class WallpaperEngine: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var currentDuration: Double?
    @Published private(set) var currentSize: CGSize?
    @Published private(set) var isActive = false
    @Published private(set) var autoPauseReason: String?
    @Published private(set) var isBatteryPaused = false

    private enum PauseReason: Hashable {
        case user
        case battery
        case locked
        case displaySleep
    }

    private let settings: Settings
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]

    private var loadedURL: URL?
    private var pauseReasons: Set<PauseReason> = []
    private var cancellables = Set<AnyCancellable>()
    private var observerTokens: [NSObjectProtocol] = []
    private var activityToken: NSObjectProtocol?
    private var batteryTimer: Timer?
    private var screenDebounce: DispatchWorkItem?
    private var metadataTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var playbackWatchdog: Timer?

    private var demoURL: URL? {
        Bundle.main.url(forResource: "Aurora", withExtension: "mp4")
    }

    init(settings: Settings) {
        self.settings = settings
        player.isMuted = settings.isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.volume = 1
    }

    // MARK: - Lifecycle

    func start() {
        bindSettings()
        installObservers()
        updateBatteryPolicy()

        if let url = settings.videoURL ?? demoURL {
            load(url: url)
        }

        playbackWatchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.ensurePlayback()
        }

        // Finder's desktop occasionally comes up after a login-item launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.reassertWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.reassertWindows()
        }
    }

    func stop() {
        metadataTask?.cancel()
        player.pause()
        looper?.disableLooping()
        player.removeAllItems()
        closeWindows()
        batteryTimer?.invalidate()
        batteryTimer = nil
        playbackWatchdog?.invalidate()
        playbackWatchdog = nil

        for token in observerTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - Public API

    /// Validates and applies a user-selected video. Returns false when the
    /// file cannot be played; the current wallpaper keeps running.
    @discardableResult
    func apply(video url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            presentError(
                title: "找不到视频文件",
                message: "「\(standardized.lastPathComponent)」可能已被移动或删除，请重新选择。"
            )
            return false
        }

        if settings.videoPath == standardized.path {
            settings.addRecent(standardized)
            if loadedURL?.standardizedFileURL != standardized {
                load(url: standardized)
            }
        } else {
            settings.setVideo(standardized)
        }
        return true
    }

    var displayTitle: String {
        guard let url = currentURL else { return "未选择视频" }
        return url.deletingPathExtension().lastPathComponent
    }

    var metadataText: String {
        guard currentURL != nil else { return "拖入一段视频开始" }
        var parts: [String] = []
        if let size = currentSize {
            parts.append("\(Int(size.width)) × \(Int(size.height))")
        }
        if let duration = currentDuration, duration > 0 {
            let total = Int(duration.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        parts.append("循环播放")
        if settings.isMuted { parts.append("静音") }
        return parts.joined(separator: "  ·  ")
    }

    func togglePlayback() {
        settings.isPaused.toggle()
    }

    /// Returns to the bundled demo loop and clears the saved selection so the
    /// demo comes back on next launch too.
    func useBuiltInDemo() {
        guard let url = demoURL else { return }
        if settings.videoPath != nil {
            settings.videoPath = nil
        }
        settings.isPaused = false
        if loadedURL?.standardizedFileURL != url.standardizedFileURL {
            load(url: url)
        } else {
            syncPlayback()
        }
    }

    // MARK: - Video loading

    private func load(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            presentError(
                title: "找不到视频文件",
                message: "「\(url.lastPathComponent)」可能已被移动或删除，请重新选择。"
            )
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        let asset = AVURLAsset(url: url)

        Task { [weak self] in
            let playable = (try? await asset.load(.isPlayable)) ?? false
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []

            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                guard playable, !tracks.isEmpty else {
                    self.presentError(
                        title: "无法播放这段视频",
                        message: "请选择 MP4、MOV 或 M4V 格式的视频文件。"
                    )
                    return
                }
                self.startPlayback(url: url, asset: asset)
            }
        }
    }

    private func startPlayback(url: URL, asset: AVAsset) {
        loadedURL = url
        currentURL = url
        currentDuration = nil
        currentSize = nil

        looper?.disableLooping()
        player.removeAllItems()

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        looper = AVPlayerLooper(player: player, templateItem: item)

        loadMetadata(of: asset, for: url)
        rebuildWindows()
        syncPlayback()
    }

    private func loadMetadata(of asset: AVAsset, for url: URL) {
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            do {
                let duration = try await asset.load(.duration)
                var size: CGSize?
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let natural = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let transformed = natural.applying(transform)
                    size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                }
                let seconds = duration.isNumeric ? duration.seconds : nil
                let finalSize = size
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.currentURL?.standardizedFileURL == url.standardizedFileURL else { return }
                    self.currentDuration = seconds
                    self.currentSize = finalSize
                }
            } catch {
                // Metadata is cosmetic only; playback continues regardless.
            }
        }
    }

    // MARK: - Windows

    private func rebuildWindows() {
        guard currentURL != nil else {
            closeWindows()
            return
        }

        let screens = NSScreen.screens
        let validIDs = Set(screens.compactMap { $0.displayID })

        for (id, window) in windows where !validIDs.contains(id) {
            window.orderOut(nil)
            window.close()
            windows.removeValue(forKey: id)
        }

        for screen in screens {
            guard let id = screen.displayID else { continue }
            if let window = windows[id] {
                window.updateFrame(from: screen)
                window.setGravity(settings.fillMode.videoGravity)
                window.orderFrontRegardless()
            } else {
                windows[id] = WallpaperWindow(
                    screen: screen,
                    player: player,
                    gravity: settings.fillMode.videoGravity
                )
            }
        }
    }

    private func closeWindows() {
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func reassertWindows() {
        guard currentURL != nil else { return }
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            if let window = windows[id] {
                window.updateFrame(from: screen)
                window.orderFrontRegardless()
            } else {
                rebuildWindows()
                return
            }
        }
    }

    private func screensChanged() {
        screenDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildWindows()
            self?.reassertWindows()
        }
        screenDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Playback state

    private func bindSettings() {
        settings.$isMuted
            .removeDuplicates()
            .sink { [weak self] muted in
                self?.player.isMuted = muted
            }
            .store(in: &cancellables)

        settings.$fillMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.windows.values.forEach { $0.setGravity(mode.videoGravity) }
            }
            .store(in: &cancellables)

        settings.$isPaused
            .removeDuplicates()
            .sink { [weak self] paused in
                self?.setPause(.user, active: paused)
            }
            .store(in: &cancellables)

        settings.$batterySaver
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateBatteryPolicy()
            }
            .store(in: &cancellables)

        settings.$pauseOnLock
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, !enabled else { return }
                self.setPause(.locked, active: false)
                self.setPause(.displaySleep, active: false)
            }
            .store(in: &cancellables)

        settings.$videoPath
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] path in
                guard let self, let path,
                      self.loadedURL?.path != path,
                      FileManager.default.fileExists(atPath: path) else { return }
                self.load(url: URL(fileURLWithPath: path))
            }
            .store(in: &cancellables)
    }

    private func setPause(_ reason: PauseReason, active: Bool) {
        if active {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
        syncPlayback()
    }

    private func syncPlayback() {
        guard currentURL != nil else {
            player.pause()
            isActive = false
            autoPauseReason = nil
            isBatteryPaused = false
            updateActivity()
            return
        }

        let shouldPause = !pauseReasons.isEmpty
        if shouldPause {
            player.pause()
        } else {
            player.play()
        }

        isActive = !shouldPause
        autoPauseReason = pauseDescription
        isBatteryPaused = pauseReasons.contains(.battery)
        updateActivity()
    }

    private var pauseDescription: String? {
        if pauseReasons.contains(.battery) { return "电池供电，壁纸已自动暂停" }
        if pauseReasons.contains(.locked) { return "屏幕已锁定，壁纸已自动暂停" }
        if pauseReasons.contains(.displaySleep) { return "显示器已休眠，壁纸已自动暂停" }
        return nil
    }

    /// Recovers if the player silently stalls (for example after a display
    /// wake or a system audio/video interruption).
    private func ensurePlayback() {
        guard isActive, currentURL != nil else { return }
        if player.timeControlStatus != .playing {
            player.play()
        }
    }

    private func updateActivity() {
        if isActive {
            if activityToken == nil {
                activityToken = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
                    reason: "Playing desktop wallpaper"
                )
            }
        } else if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - Battery policy

    private func updateBatteryPolicy() {
        batteryTimer?.invalidate()
        batteryTimer = nil

        guard settings.batterySaver else {
            setPause(.battery, active: false)
            return
        }

        evaluateBattery()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.evaluateBattery()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    private func evaluateBattery() {
        let onBattery = PowerSource.isOnBattery || ProcessInfo.processInfo.isLowPowerModeEnabled
        setPause(.battery, active: onBattery)
    }

    // MARK: - System notifications

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.settings.pauseOnLock else { return }
            self.setPause(.displaySleep, active: true)
        })

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.setPause(.displaySleep, active: false)
            self.reassertWindows()
        })

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.settings.pauseOnLock else { return }
            self.setPause(.displaySleep, active: true)
        })

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.setPause(.displaySleep, active: false)
            self.reassertWindows()
        })

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.settings.pauseOnLock else { return }
            self.setPause(.locked, active: true)
        })

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.setPause(.locked, active: false)
        })

        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Desktop-level windows can be left behind when Spaces switch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.reassertWindows()
            }
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.settings.batterySaver else { return }
            self.evaluateBattery()
        })
    }

    // MARK: - Errors

    private func presentError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
