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
    @State private var llmAvailable: Bool?

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
                        if prefs.metadataBackend == .auto && llmAvailable == false {
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
        .task { llmAvailable = await FoundationModelsBackend().isAvailable() }
    }

    /// What will *actually* run, which is not always what is selected.
    private var activeIsLLM: Bool {
        prefs.metadataBackend == .auto && llmAvailable == true
    }

    private var activeExplanation: String {
        if activeIsLLM {
            return "Apple Intelligence is on, so titles, summaries, decisions and action items are written by the model built into macOS. It runs on this Mac."
        }
        if prefs.metadataBackend == .heuristic {
            return "You have pinned this option. Titles and summaries are built by selecting the most salient sentences and phrases from the transcript — no model, and the same transcript always gives the same result."
        }
        switch llmAvailable {
        case false:
            return "Apple Intelligence is switched off on this Mac, so there is no language model to use. Titles and summaries are built by selecting the most salient sentences and phrases from the transcript — the same transcript always gives the same result. Nothing is invented: every decision and action item cites the timestamp it came from."
        case nil:
            return "Checking what is available…"
        default:
            return ""
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: Tok.s3) {
            Text("•").font(.caption).foregroundStyle(Tok.textSecondary)
            Text(s).font(.caption).foregroundStyle(Tok.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
