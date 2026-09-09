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

        section("Audio")
        if let device = OutputDeviceMonitor.current() {
            print("  output device:      \(device.name ?? "unnamed") "
                  + "(\(device.transport)/\(device.dataSource ?? "-"))")
            switch device.kind.echoPossible {
            case true?:
                print("  echo possible:      yes — the call can reach your microphone")
                print("  → headphones prevent it. Minutes counts the far end once either way.")
            case false?:
                print("  echo possible:      no — sound is going into your ears")
            case nil:
                print("  echo possible:      unknown — this transport cannot say")
                print("  → Core Audio reports AirPods and a Bluetooth speaker identically,")
                print("    so the correlation detector decides on this device.")
            }
        } else {
            print("  output device:      none reported")
        }

        section("Transcription")
        let model = await MainActor.run { Preferences.shared.model }
        print("  active model:       \(model)")
        let downloaded = await MainActor.run { ModelCatalog.isDownloaded(model) }
        print("  downloaded:         \(downloaded)")
        print("  model store:        \(ModelStorage.base.path)")

        section("Summaries")
        // FR-109. The *reason*, so "it says Apple Intelligence is off and it
        // isn't" is answerable without reading source. It was previously
        // reported nowhere and inferred wrongly in the UI.
        let llm = await FoundationModelsBackend().availability()
        let choice = await MainActor.run { Preferences.shared.metadataBackend }
        print("  on-device model:    \(llm.summary)")
        print("  your choice:        \(choice == .auto ? "use the model when available" : "always keyphrase extraction")")
        let willRun = (choice == .auto && llm.isUsable) ? "Apple's on-device model" : "keyphrase extraction"
        print("  will actually run:  \(willRun)")
        if !llm.isUsable, llm.settingsCanHelp {
            print("  → System Settings › Apple Intelligence & Siri says whether the models")
            print("    are still downloading or an organisation is restricting them.")
        }

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

        section("Version")
        print("  version:            \(AppVersion.short) (\(AppVersion.build))")
        print("  built from:         \(AppVersion.describe)")
        if !AppVersion.isRelease {
            print("  NOTE:               development build, not a tagged release")
        }

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

        // FR-78. The one part of increment 7 that can be checked from a terminal
        // against the real library: whether every Note is actually findable, and
        // whether any file in the folder is orphaned. Counts and states only —
        // never a title, never a filename (PRD §9.1, Story 13.5).
        section("Note links")
        if let f = folder {
            let links = await NoteLinkService.reconcile(meetings, in: f)
            var linked = 0, userNamed = 0, notFound = 0, ambiguous = 0
            for state in links.values {
                switch state {
                case .linked(_, let byUser): linked += 1; if byUser { userNamed += 1 }
                case .notFound: notFound += 1
                case .ambiguous: ambiguous += 1
                case .unknown: break
                }
            }
            print("  linked:             \(linked)")
            print("  named by you:       \(userNamed)")
            print("  NOT FOUND:          \(notFound)")
            print("  AMBIGUOUS:          \(ambiguous)")
            let orphans = await NoteLinkService.unclaimed(meetings, in: f)
            print("  unclaimed notes:    \(orphans.count)")
            let stamped = meetings.filter { $0.noteDigest != nil }.count
            print("  with a digest:      \(stamped) of \(meetings.count)   (the rest use the mtime signal, AD-41)")
        } else {
            print("  no notes folder, so nothing has been looked for")
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
