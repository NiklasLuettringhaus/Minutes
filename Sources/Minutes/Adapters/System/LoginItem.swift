import Foundation
import ServiceManagement

/// FR-45. Off by default — the app does not install itself into login items
/// uninvited.
///
/// Two mechanisms, because the modern one does not work here. `SMAppService`
/// needs a signing identity it can trust, and this build is ad-hoc signed with no
/// Team ID, so `SMAppService.mainApp.status` reports `.notFound` even from
/// `/Applications/Minutes.app`. That disabled the toggle behind a message blaming
/// the app bundle, which was both wrong and unactionable.
///
/// So: use `SMAppService` when it is available — a Developer ID build gets the
/// better mechanism for free, including the System Settings entry — and otherwise
/// fall back to a plain LaunchAgent in the user's own `~/Library/LaunchAgents`,
/// which needs no signature and no privileges.
enum LoginItem {

    /// Whether the modern API can see this app at all.
    private static var serviceAvailable: Bool {
        SMAppService.mainApp.status != .notFound
    }

    static var isEnabled: Bool {
        serviceAvailable ? SMAppService.mainApp.status == .enabled : LaunchAgent.isInstalled
    }

    static func setEnabled(_ on: Bool) throws {
        guard serviceAvailable else { try LaunchAgent.setInstalled(on); return }
        if on {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
    }

    /// False only when neither mechanism can work — running the bare executable
    /// outside a bundle.
    static var isSupported: Bool { serviceAvailable || LaunchAgent.isSupported }

    /// True when the LaunchAgent fallback is in use, which the UI must say because
    /// that path only takes effect at the next login.
    static var usesLaunchAgent: Bool { !serviceAvailable }

    static var statusDescription: String {
        if !serviceAvailable {
            return "SMAppService notFound (ad-hoc signature) — using LaunchAgent fallback, installed: \(LaunchAgent.isInstalled)"
        }
        switch SMAppService.mainApp.status {
        case .notRegistered:    return "notRegistered"
        case .enabled:          return "enabled"
        case .requiresApproval: return "requiresApproval (blocked in System Settings)"
        case .notFound:         return "notFound"
        @unknown default:       return "unknown"
        }
    }
}

/// A per-user LaunchAgent. No signature, no privileges, no helper tool — macOS
/// loads `~/Library/LaunchAgents` at login, so writing the file is the whole
/// operation. Deliberately not `launchctl bootstrap`ped on enable: `RunAtLoad`
/// would fire immediately and start a second copy of a running app.
private enum LaunchAgent {
    static let label = "dev.niklas.minutes.login"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The executable inside the bundle rather than `open -a`, so the agent keeps
    /// working if the app is renamed in the Dock or another copy exists.
    private static var executablePath: String? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let exe = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: exe.path)
        else { return nil }
        return exe.path
    }

    static var isSupported: Bool { executablePath != nil }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setInstalled(_ on: Bool) throws {
        guard on else {
            if isInstalled { try FileManager.default.removeItem(at: plistURL) }
            return
        }
        guard let exe = executablePath else {
            throw MinutesError.persistenceFailed("Minutes is not running from an app bundle.")
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            // Login only, not a background daemon: no KeepAlive, and skip
            // non-GUI sessions so an ssh login never starts a menu bar app.
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                     format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Rewritten every time it is enabled, so a plist pointing at an old copy of
        // the app is corrected rather than silently kept.
        try data.write(to: plistURL, options: .atomic)
    }
}
