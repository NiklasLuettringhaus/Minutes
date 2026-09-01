import Foundation
import UserNotifications
import CoreAudio

/// `--doctor`: prints everything that decides whether Minutes works, from a
/// terminal, without clicking a menu bar item.
///
/// Written because two real failures were invisible from inside the app. Detection
/// matched a Teams call correctly and posted a prompt that notification permission
/// silently discarded; and a schema change made five stored meetings undecodable,
/// which `loadAll`'s `try?` turned into an empty-looking list. Both are one line of
/// output here.
enum Doctor {
    static func run() {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await report()
            sem.signal()
        }
        // The work hops to the main actor, so the main thread must keep pumping
        // rather than block on the semaphore.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private static func report() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        section("Notifications")
        print("  authorization:      \(describe(settings.authorizationStatus))")
        print("  alerts:             \(describe(settings.alertSetting))")
        print("  notification centre:\(describe(settings.notificationCenterSetting))")
        if settings.authorizationStatus != .authorized {
            print("  → detected meetings will appear as a floating panel instead.")
        }

        section("Detection")
        let enabled = await MainActor.run { Preferences.shared.detectionEnabled }
        print("  enabled:            \(enabled)")
        let watched = await MainActor.run { DetectionService.watched.map(\.bundleIDPrefix) }
        print("  watched prefixes:   \(watched.joined(separator: ", "))")
        let suppressed = await MainActor.run { Preferences.shared.suppressedApps }
        print("  silenced:           \(suppressed.isEmpty ? "none" : suppressed.joined(separator: ", "))")
        let all = await MainActor.run { DetectionService.allAppsUsingAudioInput() }
        print("  holding the mic:    \(all.isEmpty ? "nothing" : all.joined(separator: ", "))")
        let matched = await MainActor.run { DetectionService.appsUsingAudioInput() }
        for m in matched { print("  MATCH               \(m.appName) — \(m.bundleID)") }

        section("Transcription")
        let model = await MainActor.run { Preferences.shared.model }
        print("  active model:       \(model)")
        let downloaded = await MainActor.run { ModelCatalog.isDownloaded(model) }
        print("  downloaded:         \(downloaded)")
        print("  model store:        \(ModelStorage.base.path)")

        section("Voices")
        let voices = await SpeakerDirectory.shared.summaries()
        let enrolled = voices.first { $0.isEnrolled }
        print("  your voice:         \(enrolled == nil ? "not enrolled" : "enrolled")")
        if let e = enrolled {
            let secs = e.speechSeconds.map { String(format: "%.1f s of speech", $0) } ?? "unknown length"
            let f = ISO8601DateFormatter()
            print("  enrolled:           \(secs), recorded \(f.string(from: e.updatedAt))")
        } else {
            print("  → several voices on the mic will stay unattributed. Record one in Getting Started.")
        }
        // Counts and sample depth, not names. This output gets pasted into notes
        // and messages, and the names here are colleagues' — they are already
        // visible in Settings to the one person entitled to see them, so a
        // diagnostic gains nothing by making them portable (PRD §9.1).
        let others = voices.filter { !$0.isEnrolled }
        print("  remembered:         \(others.count) other voice(s)")
        if !others.isEmpty {
            print("  sample depth:       \(others.map { String($0.samples) }.joined(separator: ", ")) meeting(s) — names in Settings › General")
        }
        // Never print a centroid. The counts are diagnosable; the vectors are the
        // sensitive part (PRD §9.1).
        print("  match threshold:    \(VoiceMatch.sameSpeakerThreshold) (calibrated 2026-09-01, not a setting)")
        print("  ambiguity margin:   \(VoiceMatch.ambiguityMargin)")

        section("Startup")
        print("  bundle path:        \(Bundle.main.bundlePath)")
        print("  SMAppService:       \(LoginItem.statusDescription)")
        print("  toggle available:   \(LoginItem.isSupported)")
        print("  registered:         \(LoginItem.isEnabled)")

        section("Output")
        let folder = await MainActor.run { Preferences.shared.notesFolder() }
        print("  notes folder:       \(folder?.path ?? "UNAVAILABLE")")
        if let f = folder {
            let writable = FileManager.default.isWritableFile(atPath: f.path)
            print("  writable:           \(writable)")
            let notes = (try? FileManager.default.contentsOfDirectory(atPath: f.path))?
                .filter { $0.hasSuffix(".md") } ?? []
            print("  notes on disk:      \(notes.count)")
        }

        section("Meetings")
        let store = MeetingStore.shared
        let (meetings, bad) = await store.loadAllReportingFailures()
        print("  readable:           \(meetings.count)")
        print("  UNREADABLE:         \(bad.count)")
        for b in bad { print("    ✗ \(b.id): \(b.reason.prefix(160))") }
        print("  meetings root:      \(await store.meetingsRoot.path)")
        print("  audio on disk:      \(bytes(await store.audioBytes()))")
        for m in meetings {
            let audio = await store.hasAudio(id: m.id) ? "audio" : "no audio"
            let note = m.noteFilename ?? "no note"
            print("    \(m.id)  \(m.stage.rawValue.padded(11)) \(audio.padded(9)) \(note)")
        }

        print("")
    }

    private static func section(_ t: String) {
        print("")
        print("== \(t) " + String(repeating: "=", count: max(0, 60 - t.count)))
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private static func describe(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "not asked yet"
        case .denied:        return "DENIED — prompts cannot be delivered"
        case .authorized:    return "authorized"
        case .provisional:   return "provisional"
        case .ephemeral:     return "ephemeral"
        @unknown default:    return "unknown(\(s.rawValue))"
        }
    }

    private static func describe(_ s: UNNotificationSetting) -> String {
        switch s {
        case .enabled: return "enabled"
        case .disabled: return "DISABLED"
        case .notSupported: return "not supported"
        @unknown default: return "unknown(\(s.rawValue))"
        }
    }
}

private extension String {
    /// `String(format: "%-11s")` crashes on a Swift string; this is the safe form.
    func padded(_ n: Int) -> String {
        count >= n ? self : self + String(repeating: " ", count: n - count)
    }
}
