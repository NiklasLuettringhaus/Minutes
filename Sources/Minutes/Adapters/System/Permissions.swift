import Foundation
import AVFoundation
import AppKit

/// Two permissions with wildly asymmetric ergonomics (PRD §12).
///
/// The microphone has a real request API and a queryable state, so it is reported
/// as fact. **System-audio capture has neither** — macOS exposes no way to request
/// it directly or to query it. Its state can only be *inferred* from whether a
/// capture actually produced audio, and the UI must never claim more certainty
/// than that (FR-42).
enum Permissions {

    enum MicState {
        case authorized, denied, notDetermined, restricted

        var isAuthorized: Bool { self == .authorized }
        var label: String {
            switch self {
            case .authorized: return "Granted"
            case .denied: return "Denied"
            case .notDetermined: return "Not yet requested"
            case .restricted: return "Restricted by policy"
            }
        }
    }

    static func micState() -> MicState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Inference, never a claim of certainty.
    enum SystemAudioState {
        /// A capture produced non-silent system audio.
        case observedWorking
        /// A capture ran and produced nothing.
        case observedNotWorking
        /// No capture has been attempted yet, so we genuinely do not know.
        case unknown

        var label: String {
            switch self {
            case .observedWorking: return "Last recording captured system audio"
            case .observedNotWorking: return "Last recording captured no system audio"
            case .unknown: return "Not tested yet"
            }
        }
    }

    @MainActor
    static func systemAudioState() -> SystemAudioState {
        switch Preferences.shared.lastSystemCaptureOK {
        case .some(true): return .observedWorking
        case .some(false): return .observedNotWorking
        case nil: return .unknown
        }
    }

    static let bundleID = "dev.niklas.minutes"

    /// The app is ad-hoc signed, so consent is invalidated whenever the binary
    /// changes. This is the single most likely cause of "it stopped working",
    /// so the command is surfaced rather than buried (FR-42).
    static let resetCommand = """
        tccutil reset SystemAudioCaptureRequests \(bundleID)
        tccutil reset Microphone \(bundleID)
        """

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    /// `Privacy_AudioCapture` verified present in
    /// `SecurityPrivacyExtension.appex` on macOS 26 — the previous generic
    /// `?Privacy` anchor landed the user on the Privacy root and left them to find
    /// the right list themselves. An unrecognised anchor still falls back there,
    /// so naming it costs nothing.
    static func openSystemAudioSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }

    /// The Apple Intelligence & Siri pane (FR-109).
    ///
    /// `com.apple.Siri-Settings.extension` is the bundle identifier of
    /// `SiriPreferenceExtension.appex`, read off this machine rather than
    /// guessed — the pane it opens is the one titled "Apple Intelligence &
    /// Siri", which is also where macOS itself says whether the models are still
    /// downloading or an organisation is restricting them. Minutes does not try
    /// to answer those questions; it takes the user to the place that can.
    static func openAppleIntelligenceSettings() {
        open("x-apple.systempreferences:com.apple.Siri-Settings.extension")
    }

    private static func open(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}
