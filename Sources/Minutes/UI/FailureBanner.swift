import SwiftUI

/// The reason the last thing the user asked for did not happen, and what to do
/// about it. FR-66.
///
/// This exists because `AppState.lastError` was written on four failure paths in
/// `SessionCoordinator` and read by exactly one file — `App/SelfTest.swift`, a
/// command-line path. Nothing under `UI/` read it. Declining the microphone
/// prompt left the icon grey, the menu still offering "Start Recording", and no
/// explanation anywhere, while `MinutesError` already carried the right sentence
/// and the right remedy. The strings were never the problem; nothing was
/// showing them.
///
/// It is `amberInk` rather than `recording` red: red belongs to the recording
/// state alone (DESIGN.md), and a failed start is a thing to fix, not an alarm.
struct FailureBanner: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let e = app.lastError {
            // EXPERIENCE.md: a row of controls uses ViewThatFits rather than
            // assuming a width. Rendered at 320pt the single-row form crushed the
            // reason into a column narrower than the button beside it and
            // truncated the button to "Open Audio Settin…".
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Tok.s3) {
                    glyph
                    message(e)
                    Spacer(minLength: Tok.s3)
                    controls(e)
                }
                VStack(alignment: .leading, spacing: Tok.s3) {
                    HStack(alignment: .top, spacing: Tok.s3) {
                        glyph
                        message(e)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: Tok.s3) {
                        Spacer(minLength: 0)
                        controls(e)
                    }
                }
            }
            .padding(Tok.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tok.surfaceCard, in: RoundedRectangle(cornerRadius: Tok.rMd))
            .overlay(
                RoundedRectangle(cornerRadius: Tok.rMd)
                    .strokeBorder(Tok.amberInk.opacity(0.45), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }

    private var glyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Tok.amberInk)
            .accessibilityHidden(true)
    }

    private func message(_ e: MinutesError) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(e.errorDescription ?? "Something went wrong.")
                .font(.callout).fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            if let s = e.recoverySuggestion {
                Text(s)
                    .font(.caption).foregroundStyle(Tok.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func controls(_ e: MinutesError) -> some View {
        if let r = e.remedy {
            Button(r.label) { Self.perform(r) }
                .buttonStyle(.bordered).controlSize(.small)
                .fixedSize()
        }
        Button {
            app.lastError = nil
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Dismiss")
    }

    /// Core names the remedy as a value; the mapping to an AppKit call lives here,
    /// because `MinutesError` depends on Foundation alone.
    static func perform(_ r: MinutesError.Remedy) {
        switch r {
        case .openMicrophoneSettings:   Permissions.openMicrophoneSettings()
        case .openSystemAudioSettings:  Permissions.openSystemAudioSettings()
        case .chooseTranscriptionModel: AppState.shared.paneRequest = MainWindow.Pane.transcription.rawValue
        case .chooseNotesFolder:        AppState.shared.paneRequest = MainWindow.Pane.general.rawValue
        }
    }
}
