import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    private(set) lazy var engine = WallpaperEngine(settings: settings)
    private(set) lazy var layoutManager = DesktopLayoutManager()

    private var menuBar: MenuBarController!
    private var preferences: PreferencesController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let iconController = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "")
        if let iconController {
            NSApp.applicationIconImage = iconController
        }

        preferences = PreferencesController(
            settings: settings,
            engine: engine,
            layoutManager: layoutManager,
            chooseVideo: { [weak self] in self?.chooseVideo() }
        )

        menuBar = MenuBarController(settings: settings, engine: engine, layoutManager: layoutManager)
        menuBar.onChooseVideo = { [weak self] in self?.chooseVideo() }
        menuBar.onOpenPreferences = { [weak self] in self?.showPreferences() }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.install()

        engine.start()
        layoutManager.start()

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--video"), index + 1 < arguments.count {
            engine.apply(video: URL(fileURLWithPath: arguments[index + 1]))
        }

        // Hidden diagnostics used to verify the desktop-layout pipeline without UI automation.
        if arguments.contains("--save-layout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                let result = self?.layoutManager.saveCurrentLayout()
                print("LAYOUT_SAVE: \(result?.message ?? "no manager")")
                fflush(stdout)
                NSApp.terminate(nil)
            }
            return
        }
        if arguments.contains("--restore-layout") {
            layoutManager.restoreCurrentLayout { message in
                print("LAYOUT_RESTORE: \(message)")
                fflush(stdout)
                NSApp.terminate(nil)
            }
            return
        }

        if arguments.contains("--preferences") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPreferences()
            }
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didCompleteFirstLaunch") {
            defaults.set(true, forKey: "didCompleteFirstLaunch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.showPreferences()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.isFileURL }) else { return }
        engine.apply(video: url)
    }

    // MARK: - Main menu

    /// The app is LSUIElement, but a small main menu makes the standard
    /// shortcuts (⌘Q, ⌘W, copy/paste) work while the settings window is open.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Wallflow")
        appMenu.addItem(withTitle: "关于 Wallflow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Wallflow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Wallflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Actions

    func showPreferences() {
        settings.refreshLaunchAtLogin()
        preferences.show()
    }

    func chooseVideo() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "选择壁纸视频"
        panel.message = "支持 MP4、MOV、M4V 格式，建议使用可无缝循环的视频"
        panel.prompt = "设为壁纸"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine.apply(video: url)
    }
}
