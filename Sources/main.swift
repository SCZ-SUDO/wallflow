import AppKit

// Wallflow is a menu-bar-only app. Everything lives in AppDelegate so the
// wallpaper windows can be managed alongside the status item.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
