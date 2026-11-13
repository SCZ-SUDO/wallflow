import AppKit
import AVFoundation

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// A borderless window that sits above the system wallpaper but below the
/// desktop icons, on every Space, on a single display.
final class WallpaperWindow: NSWindow {
    private let wallpaperView: WallpaperView

    init(screen: NSScreen, player: AVPlayer, gravity: AVLayerVideoGravity) {
        wallpaperView = WallpaperView(player: player, gravity: gravity)

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Desktop level is above the system wallpaper and below Finder's icons.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        isRestorable = false
        animationBehavior = .none
        title = "Wallflow"

        contentView = wallpaperView
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setGravity(_ gravity: AVLayerVideoGravity) {
        wallpaperView.playerLayer.videoGravity = gravity
    }

    func updateFrame(from screen: NSScreen) {
        if frame != screen.frame {
            setFrame(screen.frame, display: true)
        }
    }
}

final class WallpaperView: NSView {
    let playerLayer: AVPlayerLayer

    init(player: AVPlayer, gravity: AVLayerVideoGravity) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = gravity
        playerLayer.backgroundColor = NSColor.black.cgColor

        super.init(frame: .zero)

        wantsLayer = true
        layer = playerLayer
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
