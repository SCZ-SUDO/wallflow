import AppKit
import Combine
import CoreGraphics

// MARK: - Models

struct DisplaySnapshot: Codable, Equatable, Identifiable {
    let uuid: String
    let name: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let isMain: Bool

    var id: String { uuid }
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct IconSnapshot: Codable, Equatable {
    let name: String
    let x: Double
    let y: Double
}

struct DesktopLayoutProfile: Codable, Equatable, Identifiable {
    let signature: String
    let name: String
    let displays: [DisplaySnapshot]
    let icons: [IconSnapshot]
    let savedAt: Date

    var id: String { signature }
    var iconCount: Int { icons.count }
}

struct LayoutActionResult {
    let success: Bool
    let message: String

    static func ok(_ message: String) -> LayoutActionResult {
        LayoutActionResult(success: true, message: message)
    }

    static func fail(_ message: String) -> LayoutActionResult {
        LayoutActionResult(success: false, message: message)
    }
}

enum LayoutError: Error {
    case permissionDenied
    case script(String)

    var message: String {
        switch self {
        case .permissionDenied:
            return "Wallflow 没有控制 Finder 的权限。请到「系统设置 → 隐私与安全性 → 自动化」里勾选 Wallflow 的 Finder。"
        case .script(let message):
            return "Finder 脚本失败：\(message)"
        }
    }
}

// MARK: - Manager

/// Saves and restores the display arrangement and Finder desktop icon positions
/// per display combination (e.g. single built-in vs. external + built-in).
final class DesktopLayoutManager: ObservableObject {
    @Published private(set) var profiles: [String: DesktopLayoutProfile] = [:]
    @Published private(set) var currentSignature = ""
    @Published private(set) var currentSummary = "正在读取显示器…"
    @Published private(set) var pendingProfile: DesktopLayoutProfile?
    @Published private(set) var lastMessage = ""

    @Published var autoRestore: Bool {
        didSet { defaults.set(autoRestore, forKey: Self.autoKey) }
    }

    private static let profilesKey = "desktopLayoutProfiles"
    private static let autoKey = "desktopLayoutAutoRestore"

    private let defaults = UserDefaults.standard
    private var screenObserver: NSObjectProtocol?
    private var screenDebounce: DispatchWorkItem?

    init() {
        let storedAuto = defaults.bool(forKey: Self.autoKey)
        autoRestore = storedAuto
        loadProfiles()
        refreshCurrentState()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScreenChange()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenDebounce?.cancel()
    }

    func start() {
        refreshCurrentState()
    }

    var currentProfile: DesktopLayoutProfile? {
        profiles[currentSignature]
    }

    var hasProfileForCurrentLayout: Bool {
        currentProfile != nil
    }

    // MARK: - Save

    @discardableResult
    func saveCurrentLayout() -> LayoutActionResult {
        let displays = currentDisplays()
        guard !displays.isEmpty else {
            return .fail("没有检测到可用显示器。")
        }

        let signature = Self.signature(for: displays)
        let name = Self.profileName(for: displays)
        let bounds = Self.desktopBounds(for: displays)

        var icons: [IconSnapshot] = []
        var warning: String?
        switch captureIcons(in: bounds) {
        case .success(let captured):
            icons = captured
        case .failure(let error):
            warning = error.message
        }

        let profile = DesktopLayoutProfile(
            signature: signature,
            name: name,
            displays: displays,
            icons: icons,
            savedAt: Date()
        )
        profiles[signature] = profile
        persistProfiles()
        currentSignature = signature
        currentSummary = Self.summary(for: displays)
        pendingProfile = nil

        var message = "已保存「\(name)」：\(displays.count) 台显示器，\(icons.count) 个桌面图标。"
        if let warning {
            message += "\n\n显示器排列已保存，但桌面图标没有保存：\(warning)"
        }
        lastMessage = message
        return LayoutActionResult(success: true, message: message)
    }

    // MARK: - Restore

    func restoreCurrentLayout(completion: ((String) -> Void)? = nil) {
        guard let profile = profiles[currentSignature] else {
            let message = "当前显示器组合还没有保存布局。先点「保存当前布局」。"
            lastMessage = message
            completion?(message)
            return
        }
        restore(profile: profile, automatic: false, completion: completion)
    }

    private func restore(
        profile: DesktopLayoutProfile,
        automatic: Bool,
        completion: ((String) -> Void)?
    ) {
        let displays = currentDisplays()
        let currentSignature = Self.signature(for: displays)
        guard currentSignature == profile.signature else {
            let message = "显示器组合已经变了，保存的「\(profile.name)」不再适用于当前屏幕。"
            lastMessage = message
            pendingProfile = profile
            completion?(message)
            return
        }

        let savedMain = profile.displays.first(where: { $0.isMain })
        let currentMain = displays.first(where: { $0.isMain })
        if let savedMain, let currentMain, savedMain.uuid != currentMain.uuid {
            let message = """
            主屏不一致：保存时主屏是「\(savedMain.name)」，现在是「\(currentMain.name)」。
            macOS 不允许应用直接改主屏，请先在「系统设置 → 显示器」里把主屏切回去，再点恢复。
            """
            lastMessage = message
            pendingProfile = profile
            completion?(message)
            return
        }

        let originResult = applyOrigins(profile.displays)

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            var messages: [String] = []
            var hadError = originResult.message != nil
            if let note = originResult.message {
                messages.append(note)
            }

            if profile.icons.isEmpty {
                messages.append("没有保存的桌面图标可恢复。")
            } else {
                let bounds = Self.desktopBounds(for: self.currentDisplays())
                switch self.applyIcons(profile.icons, in: bounds, activateApp: !automatic) {
                case .success(let moved):
                    messages.append("已恢复 \(moved) 个桌面图标。")
                case .failure(let error):
                    hadError = true
                    messages.append(error.message)
                }
            }

            let prefix = originResult.changed ? "已恢复显示器排列。" : "显示器排列无需调整。"
            let message = "\(prefix)「\(profile.name)」\n" + messages.joined(separator: "\n")
            self.pendingProfile = (automatic && hadError) ? profile : nil
            self.lastMessage = message
            if !automatic {
                completion?(message)
            }
        }

        if originResult.changed {
            // Give WindowServer / Finder a moment to settle before moving icons.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: finish)
        } else {
            finish()
        }
    }

    // MARK: - Display state

    private func scheduleScreenChange() {
        screenDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.handleScreenChange()
        }
        screenDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func handleScreenChange() {
        let oldSignature = currentSignature
        refreshCurrentState()
        guard currentSignature != oldSignature else { return }

        if let profile = profiles[currentSignature] {
            if autoRestore {
                pendingProfile = profile
                restore(profile: profile, automatic: true, completion: nil)
            } else {
                pendingProfile = profile
                lastMessage = "显示器变化，可恢复「\(profile.name)」布局。"
            }
        } else {
            pendingProfile = nil
            lastMessage = "当前显示器组合还没有保存布局。"
        }
    }

    private func refreshCurrentState() {
        let displays = currentDisplays()
        currentSignature = Self.signature(for: displays)
        currentSummary = displays.isEmpty ? "没有检测到显示器" : Self.summary(for: displays)
    }

    private func currentDisplays() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        let screens = NSScreen.screens
        var result: [DisplaySnapshot] = []
        for id in ids.prefix(Int(count)) {
            let bounds = CGDisplayBounds(id)
            let screen = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            result.append(
                DisplaySnapshot(
                    uuid: Self.uuid(for: id),
                    name: screen?.localizedName ?? "显示器",
                    x: Double(bounds.origin.x),
                    y: Double(bounds.origin.y),
                    width: Double(bounds.width),
                    height: Double(bounds.height),
                    isMain: CGDisplayIsMain(id) != 0
                )
            )
        }
        return result.sorted { $0.uuid < $1.uuid }
    }

    private func applyOrigins(_ saved: [DisplaySnapshot]) -> (changed: Bool, message: String?) {
        let displays = currentDisplays()
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return (false, "无法修改显示器排列：CGBeginDisplayConfiguration 失败。")
        }

        var changed = false
        var errors: [String] = []

        for snapshot in saved {
            guard let current = displays.first(where: { $0.uuid == snapshot.uuid }) else { continue }
            guard let id = Self.displayID(forUUID: snapshot.uuid) else { continue }
            if abs(current.x - snapshot.x) < 0.5 && abs(current.y - snapshot.y) < 0.5 {
                continue
            }
            let error = CGConfigureDisplayOrigin(
                config,
                id,
                Int32(snapshot.x.rounded()),
                Int32(snapshot.y.rounded())
            )
            if error == .success {
                changed = true
            } else {
                errors.append("「\(snapshot.name)」排列设置失败（\(error.rawValue)）")
            }
        }

        if !changed {
            CGCompleteDisplayConfiguration(config, .forSession)
            return (false, errors.isEmpty ? nil : errors.joined(separator: "；"))
        }

        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        if complete != .success {
            errors.append("显示器排列保存失败（\(complete.rawValue)）")
        }
        return (true, errors.isEmpty ? nil : errors.joined(separator: "；"))
    }

    // MARK: - Finder desktop icons

    private func captureIcons(in bounds: CGRect) -> Result<[IconSnapshot], LayoutError> {
        let source = """
        tell application "Finder"
            set out to ""
            set names to name of every item of desktop
            set positions to position of every item of desktop
            repeat with i from 1 to count of names
                set p to item i of positions
                set out to out & (item i of names) & (ASCII character 31) & (item 1 of p) & (ASCII character 31) & (item 2 of p) & (ASCII character 30)
            end repeat
            return out
        end tell
        """

        switch runAppleScript(source, activateApp: true) {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            guard let text = descriptor.stringValue, !text.isEmpty else {
                return .success([])
            }
            let validBounds = bounds.insetBy(dx: -80, dy: -80)
            var icons: [IconSnapshot] = []
            for record in text.split(separator: "\u{1E}", omittingEmptySubsequences: true) {
                let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false)
                guard fields.count >= 3,
                      let x = Double(fields[1]),
                      let y = Double(fields[2]) else { continue }
                let name = String(fields[0])
                guard validBounds.contains(CGPoint(x: x, y: y)) else { continue }
                icons.append(IconSnapshot(name: name, x: x, y: y))
            }
            return .success(icons)
        }
    }

    private func applyIcons(
        _ icons: [IconSnapshot],
        in bounds: CGRect,
        activateApp: Bool
    ) -> Result<Int, LayoutError> {
        let validBounds = bounds.insetBy(dx: -80, dy: -80)
        let valid = icons.filter { validBounds.contains(CGPoint(x: $0.x, y: $0.y)) }
        guard !valid.isEmpty else { return .success(0) }

        var lines = [
            "tell application \"Finder\"",
            "set moved to 0",
        ]

        for icon in valid {
            guard !icon.name.contains("\u{1E}"), !icon.name.contains("\u{1F}") else { continue }
            let escaped = Self.appleScriptString(icon.name)
            lines.append("try")
            lines.append("set position of item \"\(escaped)\" of desktop to {\(Int(icon.x.rounded())), \(Int(icon.y.rounded()))}")
            lines.append("set moved to moved + 1")
            lines.append("end try")
        }

        lines.append("return moved")
        lines.append("end tell")

        switch runAppleScript(lines.joined(separator: "\n"), activateApp: activateApp) {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            return .success(Int(descriptor.int32Value))
        }
    }

    private func runAppleScript(
        _ source: String,
        activateApp: Bool
    ) -> Result<NSAppleEventDescriptor, LayoutError> {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard let script = NSAppleScript(source: source) else {
            return .failure(.script("无法创建脚本"))
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
            let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "未知错误"
            if number == -1743 {
                return .failure(.permissionDenied)
            }
            return .failure(.script(message))
        }
        return .success(result)
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let data = defaults.data(forKey: Self.profilesKey),
              let decoded = try? JSONDecoder().decode([String: DesktopLayoutProfile].self, from: data) else {
            profiles = [:]
            return
        }
        profiles = decoded
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.profilesKey)
    }

    // MARK: - Helpers

    private static func signature(for displays: [DisplaySnapshot]) -> String {
        displays.map(\.uuid).sorted().joined(separator: "|")
    }

    private static func summary(for displays: [DisplaySnapshot]) -> String {
        let countText = displays.count == 1 ? "单屏" : "\(displays.count) 屏"
        return "\(countText) · " + displays.map(\.name).joined(separator: " + ")
    }

    private static func profileName(for displays: [DisplaySnapshot]) -> String {
        let countText = displays.count == 1 ? "单屏" : "\(displays.count) 屏"
        return "\(countText)（" + displays.map(\.name).joined(separator: " + ") + "）"
    }

    private static func desktopBounds(for displays: [DisplaySnapshot]) -> CGRect {
        displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }

    private static func uuid(for displayID: CGDirectDisplayID) -> String {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return "display-\(displayID)"
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    private static func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        for id in ids.prefix(Int(count)) {
            if Self.uuid(for: id) == uuid { return id }
        }
        return nil
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
