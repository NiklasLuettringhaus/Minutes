import Foundation
import ServiceManagement

/// FR-45. Off by default — the app does not install itself into login items
/// uninvited — and takes effect without a restart.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    /// `SMAppService` requires a real bundle; running the bare executable reports
    /// `.notFound`, which is not an error worth surfacing.
    static var isSupported: Bool {
        SMAppService.mainApp.status != .notFound
    }
}
