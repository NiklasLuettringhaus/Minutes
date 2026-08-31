import Foundation
import UserNotifications
import AppKit

/// Notifications are a system affordance, not a third surface.
///
/// Actions perform without bringing the app forward — the user is mid-conversation
/// when the prompt arrives, and stealing focus from their meeting would be worse
/// than not prompting at all.
@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private enum Category {
        static let detect = "MINUTES_DETECT"
        static let ready = "MINUTES_READY"
    }
    private enum Action {
        static let record = "RECORD"
        static let notNow = "NOT_NOW"
        static let never = "NEVER"
        static let reveal = "REVEAL"
    }

    private var authorized = false

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let record = UNNotificationAction(identifier: Action.record, title: "Record", options: [])
        let notNow = UNNotificationAction(identifier: Action.notNow, title: "Not now", options: [])
        // On the notification itself, not buried in Settings — this is what keeps
        // the feature from becoming a nag (FR-15).
        let never = UNNotificationAction(identifier: Action.never, title: "Never for this app",
                                         options: [.destructive])
        let detect = UNNotificationCategory(identifier: Category.detect,
                                           actions: [record, notNow, never],
                                           intentIdentifiers: [], options: [])
        let reveal = UNNotificationAction(identifier: Action.reveal, title: "Show in Finder", options: [])
        let ready = UNNotificationCategory(identifier: Category.ready, actions: [reveal],
                                           intentIdentifiers: [], options: [])
        center.setNotificationCategories([detect, ready])

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.authorized = granted
                if let error { Log.app.error("notification auth: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    /// FR-12: names the app, offers Record and a decline, and starts nothing
    /// unless Record is chosen. Ignoring it is a decline.
    func askToRecord(_ app: DetectedMeeting) {
        let c = UNMutableNotificationContent()
        c.title = "\(app.appName) is using your microphone"
        c.body = "Record this meeting?"
        c.categoryIdentifier = Category.detect
        c.userInfo = ["bundleID": app.bundleID, "appName": app.appName]
        post(c, id: "detect-\(app.bundleID)")
    }

    func meetingReady(_ m: Meeting) {
        let c = UNMutableNotificationContent()
        c.title = m.metadata?.title ?? "Meeting saved"
        var parts = [Fmt.duration(m.duration)]
        let n = m.speakers.count
        if n > 1 { parts.append("\(n) speakers") }
        if !m.systemStreamCaptured { parts.append("your mic only") }
        c.body = parts.joined(separator: " · ")
        c.categoryIdentifier = Category.ready
        c.userInfo = ["meetingID": m.id]
        post(c, id: "ready-\(m.id)")
    }

    func transcriptionFailed(_ m: Meeting, reason: String) {
        let c = UNMutableNotificationContent()
        c.title = "Transcription failed"
        c.body = reason
        c.userInfo = ["meetingID": m.id]
        post(c, id: "failed-\(m.id)")
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { Log.app.error("notify: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case Action.record:
            guard let bundleID = info["bundleID"] as? String,
                  let appName = info["appName"] as? String else { return }
            AppState.shared.pendingPrompt = nil
            await SessionCoordinator.shared.start(
                triggeredBy: DetectedMeeting(bundleID: bundleID, appName: appName))

        case Action.never:
            if let bundleID = info["bundleID"] as? String {
                // Suppress by the watched prefix, so helper-process variants are
                // covered too.
                let prefix = DetectionService.watched
                    .first { bundleID.hasPrefix($0.bundleIDPrefix) }?.bundleIDPrefix ?? bundleID
                Preferences.shared.suppress(prefix)
            }
            AppState.shared.pendingPrompt = nil

        case Action.notNow:
            AppState.shared.pendingPrompt = nil

        // Tapping the body of a detection prompt is a decline, not a record.
        case UNNotificationDefaultActionIdentifier
            where response.notification.request.content.categoryIdentifier == Category.detect:
            AppState.shared.pendingPrompt = nil

        case Action.reveal, UNNotificationDefaultActionIdentifier:
            if let id = info["meetingID"] as? String,
               let m = AppState.shared.meeting(id: id),
               let f = m.noteFilename,
               let folder = Preferences.shared.notesFolder() {
                NSWorkspace.shared.selectFile(folder.appendingPathComponent(f).path,
                                              inFileViewerRootedAtPath: folder.path)
            }

        default:
            break
        }
    }
}
