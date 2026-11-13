import AppKit
import SwiftUI

final class PreferencesController {
    private let settings: Settings
    private let engine: WallpaperEngine
    private let layoutManager: DesktopLayoutManager
    private let chooseVideo: () -> Void
    private var window: NSWindow?

    init(
        settings: Settings,
        engine: WallpaperEngine,
        layoutManager: DesktopLayoutManager,
        chooseVideo: @escaping () -> Void
    ) {
        self.settings = settings
        self.engine = engine
        self.layoutManager = layoutManager
        self.chooseVideo = chooseVideo
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let root = PreferencesView(chooseVideo: chooseVideo)
            .environmentObject(settings)
            .environmentObject(engine)
            .environmentObject(layoutManager)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 760)

        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Wallflow 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = hosting
        window.center()

        self.window = window
    }
}
