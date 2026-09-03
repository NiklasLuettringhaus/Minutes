import Foundation

/// AD-17: every adapter returns a typed error carrying a user-presentable reason.
/// No `try?` that discards a user-visible failure.
enum MinutesError: LocalizedError, Equatable {
    // Audio
    case microphonePermissionDenied
    case microphoneUnavailable(String)
    case systemAudioTapFailed(stage: String, status: Int32)
    /// The tap was established and ran, and every sample it delivered was
    /// silent. A condition the app could not previously detect at all, because
    /// elapsed time counted as proof of capture (AD-36).
    case systemAudioProducedSilence(String)
    case noDefaultOutputDevice
    /// A stream's samples were not at the rate its format declared (AD-44).
    ///
    /// The loudest failure in the audio domain, because it is the only one whose
    /// output *reads as correct*: seven recordings transcribed into fluent
    /// invented dialogue and were titled from it.
    case captureRateMismatch(stream: String, detail: String)
    case audioFileWriteFailed(String)

    // Transcription / diarization
    case modelNotDownloaded(String)
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case diarizationFailed(String)

    // Voice enrolment (FR-62). Failures are staged and named, never one generic
    // error — the user needs to know which of four things went wrong, because
    // three of them are fixed by doing something different and one is not.
    case voiceSampleUnreadable(String)
    case voiceSampleTooShort(seconds: Double)
    case voiceSampleSilent
    case voiceSampleMultipleVoices(count: Int)
    case voiceEmbeddingFailed(String)

    // Persistence
    case notesFolderUnavailable
    case notesFolderNotWritable(String)
    case persistenceFailed(String)
    /// A delete that could not reach the Trash. Deliberately **not** followed by
    /// an unlink: AD-42 exists because `removeItem` on a Meeting directory
    /// destroyed a real recording, and a fallback would restore exactly that.
    case deleteFailed(item: String, reason: String)

    // Pipeline
    case stageFailed(stage: String, reason: String)

    /// Interpolated details arrive from adapters and from the system, in no
    /// consistent case. They were invisible until FR-66 put them on screen,
    /// which is when "Transcription failed. the model returned no segments"
    /// became a thing a user could read.
    private static func sentence(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Minutes does not have permission to use the microphone."
        case .microphoneUnavailable(let d):
            return "The microphone is unavailable. \(Self.sentence(d))"
        case .systemAudioTapFailed(let stage, let status):
            return "System audio capture failed at \(stage) (OSStatus \(status))."
        case .systemAudioProducedSilence(let d):
            return "No system audio was recorded — \(d). Only your side of the meeting was captured."
        case .noDefaultOutputDevice:
            return "No default audio output device was found."
        case .captureRateMismatch(let stream, let detail):
            return "The recording of \(stream) is not usable. \(Self.sentence(detail))"
        case .audioFileWriteFailed(let d):
            return "Could not write the recording to disk. \(Self.sentence(d))"
        case .modelNotDownloaded(let m):
            return "The transcription model \(m) is not downloaded."
        case .modelLoadFailed(let d):
            return "The transcription model could not be loaded. \(Self.sentence(d))"
        case .transcriptionFailed(let d):
            return "Transcription failed. \(Self.sentence(d))"
        case .diarizationFailed(let d):
            return "Speaker separation failed. \(Self.sentence(d))"
        case .voiceSampleUnreadable(let d):
            return "The voice sample could not be read back. \(Self.sentence(d))"
        case .voiceSampleTooShort(let s):
            return String(format: "The recording was only %.1f seconds long — too short to identify a voice from.", s)
        case .voiceSampleSilent:
            return "No speech was found in the recording."
        case .voiceSampleMultipleVoices(let n):
            return "\(n) voices were in the recording, so it cannot be used."
        case .voiceEmbeddingFailed(let d):
            return "The voice sample could not be analysed. \(Self.sentence(d))"
        case .notesFolderUnavailable:
            return "The notes folder is not set or is no longer reachable."
        case .notesFolderNotWritable(let p):
            return "The notes folder is not writable: \(p)"
        case .persistenceFailed(let d):
            return "Could not save. \(Self.sentence(d))"
        case .deleteFailed(let item, let reason):
            return "\(item) was not deleted. \(Self.sentence(reason))"
        case .stageFailed(let stage, let reason):
            return "\(stage) failed. \(Self.sentence(reason))"
        }
    }

    /// Something the *app* can do about it, so the remedy is a button rather than
    /// a sentence describing where the user should click.
    ///
    /// Named as a value in Core rather than a closure, because Core depends on
    /// Foundation alone; the surface that shows the error maps it to the actual
    /// call. FR-66.
    enum Remedy: Equatable, Sendable {
        case openMicrophoneSettings
        case openSystemAudioSettings
        case chooseTranscriptionModel
        case chooseNotesFolder
        /// Runs the one thing that can distinguish a lost permission from a quiet
        /// meeting. Offered instead of a settings pane wherever the app does not
        /// actually know which of the two happened.
        case runAudioTest

        var label: String {
            switch self {
            case .openMicrophoneSettings:  return "Open Microphone Settings"
            case .openSystemAudioSettings: return "Open Audio Settings"
            case .chooseTranscriptionModel: return "Open Transcription"
            case .chooseNotesFolder:       return "Open General"
            case .runAudioTest:            return "Test Audio"
            }
        }
    }

    var remedy: Remedy? {
        switch self {
        case .microphonePermissionDenied, .microphoneUnavailable:
            return .openMicrophoneSettings
        case .systemAudioTapFailed:
            // The tap failed to establish, which *is* diagnostic.
            return .openSystemAudioSettings
        case .systemAudioProducedSilence:
            // The tap worked and heard nothing. Which of the two causes that was
            // is unknown, so offer the test rather than a fix for a guess.
            return .runAudioTest
        case .modelNotDownloaded, .modelLoadFailed:
            return .chooseTranscriptionModel
        case .notesFolderUnavailable, .notesFolderNotWritable:
            return .chooseNotesFolder
        default:
            return nil
        }
    }

    /// What the user can actually do about it. Shown alongside the description.
    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Open System Settings > Privacy & Security > Microphone and enable Minutes."
        case .microphoneUnavailable:
            return "Check that an input device is connected and selected in System Settings > Sound."
        case .audioFileWriteFailed, .persistenceFailed:
            return "Check there is free disk space, then try again."
        case .deleteFailed:
            // Nothing was removed, which is the point worth stating: the delete
            // goes to the Trash so that it can be undone, and a volume with no
            // Trash means it does not happen rather than happening irreversibly.
            return "Nothing was removed. Minutes deletes to the Trash so it can be undone, and this item could not be moved there."
        case .systemAudioTapFailed:
            return "macOS revokes system-audio permission when Minutes is rebuilt. Run the reset command shown in Settings, then try again."
        case .captureRateMismatch:
            // Names the correlation without asserting it: every one of the seven
            // observed failures had a Bluetooth headset as the *input* device,
            // and the mechanism is not proven against Apple's source.
            return "This has only been seen with a Bluetooth headset selected as the input device. Switching the input to the built-in microphone and recording again is the quickest way to get a usable recording. The audio already captured is kept, and Minutes will not write a summary from a transcript it cannot trust."
        case .systemAudioProducedSilence:
            // Deliberately two causes, because the app genuinely cannot tell them
            // apart: a revoked permission and nothing having played both deliver
            // exact digital zeros. Naming only the permission would send someone
            // who recorded a solo memo to reset TCC for nothing.
            return "Either nothing was playing on this Mac, or Minutes has lost permission to record system audio. macOS gives no way to tell those apart, so the five-second test in Getting Started is how to find out."
        case .modelNotDownloaded:
            return "Download it in Settings > Transcription."
        case .voiceSampleTooShort, .voiceSampleSilent:
            return "Record again and talk continuously — reading a paragraph out loud is enough."
        case .voiceSampleMultipleVoices:
            return "Record again somewhere nobody else is talking. A fingerprint of two people would put someone else's name on your words."
        case .voiceSampleUnreadable, .voiceEmbeddingFailed:
            return "Record again. Nothing was stored."
        case .notesFolderUnavailable, .notesFolderNotWritable:
            return "Choose a notes folder in Settings > General."
        default:
            return nil
        }
    }
}
