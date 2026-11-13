import AppKit
import AVFoundation
import Combine
import ServiceManagement

// MARK: - Fill mode

enum FillMode: String, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "填充"
        case .fit: return "适应"
        case .stretch: return "拉伸"
        }
    }

    var detail: String {
        switch self {
        case .fill: return "铺满屏幕，边缘可能被裁切"
        case .fit: return "完整显示，两侧留黑边"
        case .stretch: return "拉伸至全屏，可能变形"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}

// MARK: - Recent video

struct RecentVideo: Codable, Identifiable, Equatable {
    let path: String
    let name: String
    let addedAt: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - Settings

/// User preferences, persisted in UserDefaults. Runtime state such as
/// `isPaused` intentionally resets on every launch so the wallpaper comes
/// back to life when the app starts.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let videoPath = "videoPath"
        static let isMuted = "isMuted"
        static let fillMode = "fillMode"
        static let batterySaver = "batterySaver"
        static let pauseOnLock = "pauseOnLock"
        static let recents = "recents"
    }

    private let defaults = UserDefaults.standard

    @Published var videoPath: String? {
        didSet { defaults.set(videoPath, forKey: Key.videoPath) }
    }

    @Published var isMuted: Bool {
        didSet { defaults.set(isMuted, forKey: Key.isMuted) }
    }

    @Published var fillMode: FillMode {
        didSet { defaults.set(fillMode.rawValue, forKey: Key.fillMode) }
    }

    @Published var batterySaver: Bool {
        didSet { defaults.set(batterySaver, forKey: Key.batterySaver) }
    }

    @Published var pauseOnLock: Bool {
        didSet { defaults.set(pauseOnLock, forKey: Key.pauseOnLock) }
    }

    /// Not persisted: a fresh launch always starts playing.
    @Published var isPaused = false

    /// Mirrors `SMAppService.mainApp.status`.
    @Published var launchAtLogin: Bool = LoginItem.isEnabled

    @Published private(set) var recents: [RecentVideo] = []

    var videoURL: URL? {
        guard let path = videoPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var currentVideoName: String? {
        videoURL?.deletingPathExtension().lastPathComponent
    }

    private init() {
        if let stored = defaults.string(forKey: Key.videoPath) {
            videoPath = stored
        } else {
            videoPath = nil
        }
        isMuted = defaults.object(forKey: Key.isMuted) as? Bool ?? true
        fillMode = FillMode(rawValue: defaults.string(forKey: Key.fillMode) ?? "") ?? .fill
        batterySaver = defaults.object(forKey: Key.batterySaver) as? Bool ?? false
        pauseOnLock = defaults.object(forKey: Key.pauseOnLock) as? Bool ?? true
        loadRecents()
    }

    // MARK: Video selection

    func setVideo(_ url: URL, addToRecents: Bool = true) {
        let standardized = url.standardizedFileURL
        if videoPath != standardized.path {
            videoPath = standardized.path
        }
        if addToRecents {
            addRecent(standardized)
        }
    }

    func addRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        let name = url.deletingPathExtension().lastPathComponent
        var updated = recents.filter { $0.path != path }
        updated.insert(RecentVideo(path: path, name: name, addedAt: Date()), at: 0)
        recents = Array(updated.prefix(8))
        saveRecents()
    }

    func removeRecent(_ recent: RecentVideo) {
        recents.removeAll { $0.path == recent.path }
        saveRecents()
    }

    func clearRecents() {
        recents = []
        saveRecents()
    }

    private func loadRecents() {
        guard let data = defaults.data(forKey: Key.recents),
              let decoded = try? JSONDecoder().decode([RecentVideo].self, from: data) else {
            recents = []
            return
        }
        recents = decoded.filter(\.exists)
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        defaults.set(data, forKey: Key.recents)
    }

    // MARK: Login item

    func refreshLaunchAtLogin() {
        let enabled = LoginItem.isEnabled
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    /// Returns an error message when the login item could not be changed.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        if enabled == launchAtLogin && LoginItem.isEnabled == enabled {
            return nil
        }
        do {
            try LoginItem.set(enabled)
            launchAtLogin = LoginItem.isEnabled

            if enabled, LoginItem.requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return "Wallflow 已加入登录项，请在打开的「系统设置」中允许它开机启动。"
            }
            return nil
        } catch {
            launchAtLogin = LoginItem.isEnabled
            NSLog("[Wallflow] login item failed: \(error)")
            return error.localizedDescription
        }
    }
}
