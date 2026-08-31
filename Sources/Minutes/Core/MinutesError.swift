import Foundation

/// AD-17: every adapter returns a typed error carrying a user-presentable reason.
/// No `try?` that discards a user-visible failure.
enum MinutesError: LocalizedError, Equatable {
    // Audio
    case microphonePermissionDenied
    case microphoneUnavailable(String)
    case systemAudioTapFailed(stage: String, status: Int32)
    case noDefaultOutputDevice
    case audioFileWriteFailed(String)

    // Transcription / diarization
    case modelNotDownloaded(String)
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case diarizationFailed(String)

    // Persistence
    case notesFolderUnavailable
    case notesFolderNotWritable(String)
    case persistenceFailed(String)

    // Pipeline
    case stageFailed(stage: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Minutes does not have permission to use the microphone."
        case .microphoneUnavailable(let d):
            return "The microphone is unavailable. \(d)"
        case .systemAudioTapFailed(let stage, let status):
            return "System audio capture failed at \(stage) (OSStatus \(status))."
        case .noDefaultOutputDevice:
            return "No default audio output device was found."
        case .audioFileWriteFailed(let d):
            return "Could not write the recording to disk. \(d)"
        case .modelNotDownloaded(let m):
            return "The transcription model \(m) is not downloaded."
        case .modelLoadFailed(let d):
            return "The transcription model could not be loaded. \(d)"
        case .transcriptionFailed(let d):
            return "Transcription failed. \(d)"
        case .diarizationFailed(let d):
            return "Speaker separation failed. \(d)"
        case .notesFolderUnavailable:
            return "The notes folder is not set or is no longer reachable."
        case .notesFolderNotWritable(let p):
            return "The notes folder is not writable: \(p)"
        case .persistenceFailed(let d):
            return "Could not save. \(d)"
        case .stageFailed(let stage, let reason):
            return "\(stage) failed. \(reason)"
        }
    }

    /// What the user can actually do about it. Shown alongside the description.
    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Open System Settings > Privacy & Security > Microphone and enable Minutes."
        case .systemAudioTapFailed:
            return "macOS revokes system-audio permission when Minutes is rebuilt. Run the reset command shown in Settings, then try again."
        case .modelNotDownloaded:
            return "Download it in Settings > Transcription."
        case .notesFolderUnavailable, .notesFolderNotWritable:
            return "Choose a notes folder in Settings > General."
        default:
            return nil
        }
    }
}
