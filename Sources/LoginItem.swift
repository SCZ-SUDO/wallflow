import Foundation
import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        NSLog("[Wallflow] login item request=\(enabled) statusBefore=\(status.rawValue)")
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
        NSLog("[Wallflow] login item statusAfter=\(status.rawValue)")
    }
}
