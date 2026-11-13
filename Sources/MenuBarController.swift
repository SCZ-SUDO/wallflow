import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    var onChooseVideo: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    private let settings: Settings
    private let engine: WallpaperEngine
    private let layoutManager: DesktopLayoutManager
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(settings: Settings, engine: WallpaperEngine, layoutManager: DesktopLayoutManager) {
        self.settings = settings
        self.engine = engine
        self.layoutManager = layoutManager
        super.init()
    }

    func install() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: "Wallflow")
                ?? NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: "Wallflow")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Wallflow"
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        settings.refreshLaunchAtLogin()
        var tooltip = "Wallflow · \(engine.displayTitle)"
        if let pending = layoutManager.pendingProfile {
            tooltip += " · 可恢复「\(pending.name)」"
        }
        statusItem.button?.toolTip = tooltip

        let currentItem = NSMenuItem(
            title: engine.currentURL == nil ? "Wallflow" : "正在播放：\(shortTitle(engine.displayTitle))",
            action: nil,
            keyEquivalent: ""
        )
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        if engine.currentURL != nil {
            let reveal = makeItem("在访达中显示视频", #selector(revealCurrentVideo))
            reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(reveal)
        }

        if let pending = layoutManager.pendingProfile {
            let restore = makeItem("恢复「\(pending.name)」桌面布局", #selector(restoreDesktopLayout))
            restore.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: nil)
            menu.addItem(restore)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("选择视频…", #selector(chooseVideo), key: "o"))

        let recentsItem = NSMenuItem(title: "最近使用", action: nil, keyEquivalent: "")
        recentsItem.submenu = makeRecentsMenu()
        menu.addItem(recentsItem)
        menu.addItem(makeItem("使用内置示例壁纸", #selector(useBuiltInDemo)))

        menu.addItem(.separator())

        let pauseItem = makeItem(settings.isPaused ? "继续壁纸" : "暂停壁纸", #selector(togglePause))
        pauseItem.state = settings.isPaused ? .on : .off
        menu.addItem(pauseItem)

        if let reason = engine.autoPauseReason {
            let reasonItem = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            reasonItem.isEnabled = false
            menu.addItem(reasonItem)
        }

        let muteItem = makeItem("静音播放", #selector(toggleMute))
        muteItem.state = settings.isMuted ? .on : .off
        menu.addItem(muteItem)

        let fillItem = NSMenuItem(title: "画面填充", action: nil, keyEquivalent: "")
        let fillMenu = NSMenu()
        for mode in FillMode.allCases {
            let item = makeItem(mode.title, #selector(selectFillMode(_:)))
            item.representedObject = mode.rawValue
            item.state = settings.fillMode == mode ? .on : .off
            fillMenu.addItem(item)
        }
        fillItem.submenu = fillMenu
        menu.addItem(fillItem)

        let layoutItem = NSMenuItem(title: "桌面布局", action: nil, keyEquivalent: "")
        layoutItem.submenu = makeDesktopLayoutMenu()
        menu.addItem(layoutItem)

        menu.addItem(.separator())

        let loginItem = makeItem("开机自动启动", #selector(toggleLaunchAtLogin))
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(makeItem("设置…", #selector(openPreferences), key: ","))
        menu.addItem(makeItem("关于 Wallflow", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(makeItem("退出 Wallflow", #selector(quit), key: "q"))
    }

    private func makeDesktopLayoutMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let summary = NSMenuItem(title: layoutManager.currentSummary, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        submenu.addItem(summary)

        submenu.addItem(makeItem("保存当前布局", #selector(saveDesktopLayout)))

        let restore: NSMenuItem
        if let profile = layoutManager.currentProfile {
            restore = makeItem("恢复「\(profile.name)」", #selector(restoreDesktopLayout))
            restore.isEnabled = true
        } else {
            restore = makeItem("恢复布局", #selector(restoreDesktopLayout))
            restore.isEnabled = false
        }
        submenu.addItem(restore)

        submenu.addItem(.separator())

        let auto = makeItem("显示器变化时自动恢复", #selector(toggleAutoRestoreLayout))
        auto.state = layoutManager.autoRestore ? .on : .off
        submenu.addItem(auto)

        submenu.addItem(.separator())
        submenu.addItem(makeItem("桌面布局设置…", #selector(openPreferences)))
        return submenu
    }

    private func makeRecentsMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        guard !settings.recents.isEmpty else {
            let empty = NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }

        for recent in settings.recents {
            let item = makeItem(recent.name, #selector(openRecent(_:)))
            item.representedObject = recent.path
            item.state = recent.path == engine.currentURL?.path ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(makeItem("清除记录", #selector(clearRecents)))
        return submenu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    private func shortTitle(_ title: String) -> String {
        title.count > 32 ? String(title.prefix(31)) + "…" : title
    }

    // MARK: - Actions

    @objc private func chooseVideo() {
        onChooseVideo?()
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        engine.apply(video: URL(fileURLWithPath: path))
    }

    @objc private func clearRecents() {
        settings.clearRecents()
    }

    @objc private func useBuiltInDemo() {
        engine.useBuiltInDemo()
    }

    @objc private func togglePause() {
        engine.togglePlayback()
    }

    @objc private func toggleMute() {
        settings.isMuted.toggle()
    }

    @objc private func selectFillMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = FillMode(rawValue: raw) else { return }
        settings.fillMode = mode
    }

    @objc private func saveDesktopLayout() {
        let result = layoutManager.saveCurrentLayout()
        Alerts.show(
            title: result.success ? "已保存桌面布局" : "保存失败",
            message: result.message
        )
    }

    @objc private func restoreDesktopLayout() {
        layoutManager.restoreCurrentLayout { message in
            Alerts.show(title: "桌面布局", message: message)
        }
    }

    @objc private func toggleAutoRestoreLayout() {
        layoutManager.autoRestore.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        let target = !settings.launchAtLogin
        if let error = settings.setLaunchAtLogin(target) {
            Alerts.show(
                title: "无法设置开机启动",
                message: "\(error)\n\n如果 Wallflow 还不在「应用程序」文件夹中，请先把它拖进去再试。"
            )
        }
    }

    @objc private func revealCurrentVideo() {
        guard let url = engine.currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        onQuit?()
    }
}
