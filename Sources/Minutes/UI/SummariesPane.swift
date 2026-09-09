import SwiftUI

/// FR-52. Answers a question the user asked out loud: *what is used for
/// summarisation — I assume it's an LLM but I see no settings relating to it.*
///
/// That question had no answer anywhere in the app. FR-30 put the backend in the
/// Note's frontmatter, which is the wrong surface for "what is this app doing" —
/// you read a Note after the fact, and only if you open it.
///
/// The design risk here is the opposite of the usual one: a settings pane full of
/// controls would imply a configurable language model, and there isn't one. There
/// is no model to pick, no key, no download, and on this Mac the LLM is switched
/// off at the OS level. So this pane is mostly explanation, with exactly one
/// control, and §9.3 requires it be honest about which backend is really running.
struct SummariesPane: View {
    @EnvironmentObject var prefs: Preferences
    /// The reason, not a Bool (FR-109). Nil until the first check returns.
    @State private var llm: LanguageModelAvailability?
    @State private var rechecking = false

    var body: some View {
        PaneScaffold(title: "Summaries",
                     subtitle: "What turns a transcript into a title, tags, decisions and action items.") {

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Running now")
                Card {
                    // The glyph sits on the title's line rather than in a column of
                    // its own. An icon gutter pushed this card's text 32pt right of
                    // the radio buttons in the very next card, which is two cards on
                    // one pane starting their text at different places.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Tok.s3) {
                            Image(systemName: activeIsLLM ? "sparkles" : "function")
                                .foregroundStyle(Tok.brand)
                            Text(activeIsLLM ? "Apple's on-device language model"
                                             : "Keyphrase extraction")
                                .font(.body)
                            Spacer(minLength: 0)
                        }
                        Text(activeExplanation)
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // FR-109. A route to the setting, and only where the
                        // setting could change the answer — a button that cannot
                        // help is worse than none. The download case gets "Check
                        // again" instead, because there is nothing to change and
                        // the state resolves itself.
                        if let llm, !llm.isUsable, prefs.metadataBackend == .auto {
                            HStack(spacing: Tok.s3) {
                                if llm.settingsCanHelp {
                                    Button("Open Apple Intelligence Settings") {
                                        Permissions.openAppleIntelligenceSettings()
                                    }
                                }
                                if llm.mayResolveItself {
                                    Button(rechecking ? "Checking…" : "Check again") {
                                        Task { await recheck() }
                                    }
                                    .disabled(rechecking)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.top, Tok.s2)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Which one to use")
                Card {
                    VStack(alignment: .leading, spacing: Tok.s4) {
                        Picker(selection: Binding(
                            get: { prefs.metadataBackend },
                            set: { prefs.metadataBackend = $0 })) {
                            Text("Use the language model when it is available").tag(Preferences.MetadataBackendChoice.auto)
                            Text("Always use keyphrase extraction").tag(Preferences.MetadataBackendChoice.heuristic)
                        } label: { EmptyView() }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        Text("Applies to meetings processed from now on. Summaries already written are left alone — reprocessing a meeting would overwrite a title you may have edited.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // FR-57: say which backend runs *next*, and only when the
                        // selection and reality disagree. This used to restate what
                        // the card above already said — the same fact twice on one
                        // pane, forty lines apart, which invites the reader to hunt
                        // for the difference.
                        if prefs.metadataBackend == .auto, let llm, !llm.isUsable {
                            Text("Your choice cannot be honoured right now, so keyphrase extraction runs instead — see above.")
                                .font(.caption).foregroundStyle(Tok.amberInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "What this is not")
                Card {
                    VStack(alignment: .leading, spacing: Tok.s3) {
                        // Stated plainly because the absence of settings is exactly
                        // what made the user suspect something hidden was going on.
                        bullet("There is no cloud model. Nothing about your meetings leaves this Mac — not the audio, not the transcript, not the summary.")
                        bullet("There is no API key and nothing to sign up for.")
                        bullet("There is no summarisation model to download. The two options above are the only ones, and both are already on your Mac.")
                        bullet("Every note records which of the two wrote it, in its frontmatter, so an old note stays checkable after you change this setting.")
                    }
                }
            }
        }
        // Asked when the pane appears. The answer changes while the app runs —
        // a download finishes, the user switches Apple Intelligence on — and
        // there is no notification for it, so the "Check again" button above is
        // the honest way to ask again without navigating away.
        .task { await recheck() }
    }

    private func recheck() async {
        rechecking = true
        llm = await FoundationModelsBackend().availability()
        rechecking = false
    }

    /// What will *actually* run, which is not always what is selected.
    private var activeIsLLM: Bool {
        prefs.metadataBackend == .auto && llm?.isUsable == true
    }

    private var activeExplanation: String {
        if activeIsLLM { return LanguageModelAvailability.available.reasonForUser }
        if prefs.metadataBackend == .heuristic {
            return "You have pinned this option. Titles and summaries are built by selecting the most salient sentences and phrases from the transcript — no model, and the same transcript always gives the same result."
        }
        guard let llm else { return "Checking what is available…" }
        // The reason and the description of what runs instead are composed
        // rather than written out per case, so a corrected reason cannot leave a
        // stale second half behind it (FR-109).
        return llm.reasonForUser + " " + LanguageModelAvailability.fallbackDescription
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: Tok.s3) {
            Text("•").font(.caption).foregroundStyle(Tok.textSecondary)
            Text(s).font(.caption).foregroundStyle(Tok.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
