import SwiftUI

/// Story 2.1 / UX-DR4 — one window, grouped sidebar. Exactly one window ever
/// exists; opening from the menu brings it forward on the requested pane rather
/// than creating a second (FR-5).
struct MainWindow: View {
    enum Pane: String, CaseIterable, Identifiable {
        case gettingStarted, transcription, summaries, detection, general, meetings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .gettingStarted: return "Getting Started"
            case .transcription:  return "Transcription"
            case .summaries:      return "Summaries"
            case .detection:      return "Detection"
            case .general:        return "General"
            case .meetings:       return "Meetings"
            }
        }
        var glyph: String {
            switch self {
            case .gettingStarted: return "house"
            case .transcription:  return "waveform"
            case .summaries:      return "text.alignleft"
            case .detection:      return "sensor.tag.radiowaves.forward"
            case .general:        return "gearshape"
            case .meetings:       return "list.bullet.rectangle"
            }
        }
        var group: String {
            switch self {
            case .gettingStarted: return "Setup"
            case .transcription, .summaries, .detection, .general: return "Configure"
            case .meetings: return "Activity"
            }
        }
    }

    @EnvironmentObject var app: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var selection: Pane

    init() {
        // Getting Started on first launch, Meetings thereafter — what a returning
        // user actually wants. Selection persists across launches.
        let stored = Preferences.shared.lastPane.flatMap(Pane.init(rawValue:))
        _selection = State(initialValue: stored
            ?? (Preferences.shared.didCompleteFirstRun ? .meetings : .gettingStarted))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Setup") {
                    row(.gettingStarted)
                }
                Section("Configure") {
                    row(.transcription); row(.summaries); row(.detection); row(.general)
                }
                Section("Activity") {
                    row(.meetings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 460)
        }
        .onChange(of: selection) { _, new in
            Preferences.shared.lastPane = new.rawValue
        }
        .onChange(of: app.paneRequest) { _, req in
            guard let req, let pane = Pane(rawValue: req) else { return }
            selection = pane
            app.paneRequest = nil
        }
    }

    private func row(_ p: Pane) -> some View {
        NavigationLink(value: p) {
            Label(p.title, systemImage: p.glyph)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .gettingStarted: GettingStartedPane(selection: $selection)
        case .transcription:  TranscriptionPane()
        case .summaries:      SummariesPane()
        case .detection:      DetectionPane()
        case .general:        GeneralPane()
        case .meetings:       MeetingsPane()
        }
    }
}

/// Shared pane scaffold: title, one-line subtitle, then a stack of cards.
struct PaneScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ShotScroll {
            VStack(alignment: .leading, spacing: Tok.cardGap) {
                // Above the title, and on every pane: a failure the user needs to
                // see should not depend on which pane they happen to be looking
                // at (FR-66).
                FailureBanner()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.largeTitle)
                    Text(subtitle).font(.body).foregroundStyle(Tok.textSecondary)
                }
                content
            }
            .padding(Tok.paneMargin)
        }
        .background(Tok.surfaceWindow)
    }
}
