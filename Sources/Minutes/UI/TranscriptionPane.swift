import SwiftUI

/// FR-17 / FR-18.
///
/// Rewritten after the first version was unusable: 22 WhisperKit variants whose
/// names differed only by a stripped size suffix, every one reading
/// "Fast · Best accuracy". The complaint was exactly right — it was a catalogue,
/// not a picker. Now: a handful of choices led by what each is *for*, with the
/// identifier as a subtitle and the full list behind a disclosure.
struct TranscriptionPane: View {
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var catalog = ModelCatalog.shared
    @State private var downloading: String?
    @State private var downloadError: String?
    @State private var showAll = false

    var body: some View {
        PaneScaffold(title: "Transcription",
                     subtitle: "Which model turns your meetings into text. Everything runs on this Mac.") {

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Choose a model")
                Card {
                    ForEach(Array(catalog.entries.enumerated()), id: \.element.id) { i, e in
                        row(e, showRole: true)
                        if i < catalog.entries.count - 1 { RowDivider() }
                    }
                    if catalog.entries.isEmpty {
                        Text("No models listed yet.").font(.caption).foregroundStyle(Tok.textSecondary)
                    }
                }
            }

            if let downloadError { StateBanner(kind: .degraded, text: downloadError) }

            speedCard

            fillerCard

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Every available build", trailing: AnyView(
                    Group {
                        if catalog.isRefreshing { ProgressView().controlSize(.small) }
                        else {
                            Button(showAll ? "Hide" : "Show all \(catalog.allEntries.count)") {
                                showAll.toggle()
                                if showAll && catalog.offlineOnly {
                                    Task { await catalog.refreshFromNetwork() }
                                }
                            }
                            .buttonStyle(.borderless).font(.caption)
                        }
                    }
                ))
                if showAll {
                    Card {
                        ForEach(Array(catalog.allEntries.enumerated()), id: \.element.id) { i, e in
                            row(e, showRole: false)
                            if i < catalog.allEntries.count - 1 { RowDivider() }
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: Tok.s2) {
                            Text("You don't need this.")
                                .font(.caption.weight(.semibold))
                            Text("The \(spelled(catalog.entries.count)) models above already cover every real trade-off. The other \(max(catalog.allEntries.count - catalog.entries.count, 0)) are older releases and re-compressed copies of those same models \u{2014} \"large-v2\", \"large-v2 turbo\" and \"large-v3\" are all the same Whisper model at different vintages and sizes. Open this only if you want to pin one specific build by name.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .onAppear {
            if catalog.allEntries.isEmpty { catalog.loadLocalRecommendations() }
            catalog.refreshDownloadStates()
        }
    }

    private func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return n < words.count ? words[n] : String(n)
    }

    // MARK: - Row

    private func row(_ e: ModelCatalog.Entry, showRole: Bool) -> some View {
        let isActive = e.id == prefs.model
        return HStack(alignment: .top, spacing: Tok.s4) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Tok.brand : Tok.textSecondary)
                .font(.system(size: 15))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Tok.s3) {
                    // Provider up front — asked for directly, and it matters more
                    // now that two different engines are on offer.
                    HStack(spacing: 4) {
                        Image(systemName: e.provider.glyph).font(.system(size: 9))
                        Text(e.provider.rawValue).font(.caption2)
                    }
                    .foregroundStyle(e.provider == .nvidia ? Tok.brand : Tok.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(
                        (e.provider == .nvidia ? Tok.brand.opacity(0.12)
                                               : Tok.separator.opacity(0.45)),
                        in: RoundedRectangle(cornerRadius: Tok.rSm))
                    Text(e.name).font(.body).fontWeight(isActive ? .semibold : .medium)
                    if showRole && e.role != .other {
                        Text(e.role.rawValue.lowercased())
                            .font(.caption2)
                            .foregroundStyle(e.role == .recommended ? Tok.brand : Tok.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(
                                (e.role == .recommended ? Tok.brand.opacity(0.14)
                                                        : Tok.separator.opacity(0.5)),
                                in: Capsule())
                    }
                }
                if let note = ModelCatalog.note(for: e.id) {
                    Text(note).font(.caption).foregroundStyle(Tok.textSecondary)
                } else if showRole && !e.role.blurb.isEmpty {
                    Text(e.role.blurb).font(.caption).foregroundStyle(Tok.textSecondary)
                }
                // The identifier, so the row is never ambiguous about which model
                // it actually is.
                HStack(spacing: Tok.s3) {
                    Text(e.technical).font(.caption2).monospaced()
                    Text("· \(e.engine.rawValue)").font(.caption2)
                }
                .foregroundStyle(Tok.textSecondary)

                HStack(spacing: Tok.s5) {
                    Meter(label: "Speed", value: e.speed, tint: Tok.brand)
                    Meter(label: "Accuracy", value: e.accuracy, tint: Tok.textSecondary)
                    if let b = e.bytes {
                        Text(Fmt.bytes(b)).font(.caption2).monospacedDigit()
                            .foregroundStyle(Tok.textSecondary)
                    }
                }
                .padding(.top, 1)

                // Measured beats estimated, and the two are never conflated.
                if let r = e.measured {
                    Text("Measured here: \(ModelCatalog.projection(ratio: r, minutes: 30))")
                        .font(.caption2).foregroundStyle(Tok.brand)
                }
            }

            Spacer(minLength: Tok.s4)
            trailing(e, isActive: isActive)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { select(e) }
    }

    /// Five dots, because a relative rank is honest and a fake percentage is not.
    private struct Meter: View {
        let label: String; let value: Int; let tint: Color
        var body: some View {
            HStack(spacing: 5) {
                Text(label).font(.caption2).foregroundStyle(Tok.textSecondary)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Circle()
                            .fill(i <= value ? tint : Tok.separator)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(_ e: ModelCatalog.Entry, isActive: Bool) -> some View {
        if downloading == e.id {
            HStack(spacing: Tok.s3) {
                ProgressView().controlSize(.small)
                Text("Downloading…").font(.caption).foregroundStyle(Tok.textSecondary)
            }
        } else if e.isDownloaded {
            VStack(alignment: .trailing, spacing: 3) {
                if isActive { DonePill() }
                else {
                    Text("Downloaded").font(.caption).foregroundStyle(Tok.textSecondary)
                    Button("Remove") {
                        try? ModelCatalog.removeDownload(e.id)
                        catalog.refreshDownloadStates()
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
            }
        } else {
            RowActionButton(title: "Download", showsChevron: false) { select(e) }
        }
    }

    // MARK: - Speed reality

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "How long it takes")
            Card {
                VStack(alignment: .leading, spacing: Tok.s3) {
                    if let r = prefs.lastThroughputRatio, r > 0 {
                        Text(ModelCatalog.projection(ratio: r, minutes: 30).capitalizedFirst)
                            .font(.body)
                        Text("Measured on this Mac with \(ModelCatalog.friendlyName(prefs.model)) — \(String(format: "%.2f", r))× the length of the recording.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                    } else {
                        Text("Not measured yet.").font(.body)
                        Text("Run the test in Getting Started and this becomes a real number for your Mac instead of a guess.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                    }
                    Divider()
                    // Honest about what this design does and does not do.
                    Text("Minutes transcribes after the meeting ends, not while it runs. You get the file a few minutes later; nothing appears live.")
                        .font(.caption).foregroundStyle(Tok.textSecondary)
                    Text("Downloading a model is the only time Minutes uses the network.")
                        .font(.caption).foregroundStyle(Tok.textSecondary)
                }
            }
        }
    }

    // MARK: - Filler words

    @State private var newFiller = ""

    private var fillerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Filler words")
            Card {
                VStack(alignment: .leading, spacing: Tok.s4) {
                    Toggle(isOn: Binding(
                        get: { prefs.removeFillerWords },
                        set: { prefs.removeFillerWords = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Remove filler words").font(.body)
                            Text("Strips \u{201C}um\u{201D}, \u{201C}uh\u{201D}, \u{201C}er\u{201D} and the like from transcripts. Whole words only \u{2014} never inside another word.")
                                .font(.caption).foregroundStyle(Tok.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if prefs.removeFillerWords {
                        Divider()
                        Text("Words to remove").font(.caption).foregroundStyle(Tok.textSecondary)
                        FlowChips(items: prefs.fillerWords) { prefs.removeFillerWord($0) }
                        HStack(spacing: Tok.s3) {
                            TextField("Add a word", text: $newFiller)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { commitFiller() }
                            Button("Add") { commitFiller() }
                                .controlSize(.small)
                                .disabled(newFiller.trimmingCharacters(in: .whitespaces).isEmpty)
                            Spacer()
                            Button("Reset") { prefs.resetFillerWords() }
                                .buttonStyle(.borderless).font(.caption)
                        }
                        Text("Applies to meetings recorded from now on. Existing notes are unchanged.")
                            .font(.caption2).foregroundStyle(Tok.textSecondary)
                    }
                }
            }
        }
    }

    private func commitFiller() {
        prefs.addFillerWord(newFiller)
        newFiller = ""
    }

    // MARK: - Selection

    private func select(_ e: ModelCatalog.Entry) {
        downloadError = nil
        if e.isDownloaded { prefs.model = e.id; catalog.refreshDownloadStates(); return }
        guard downloading == nil else { return }
        downloading = e.id
        Task {
            do {
                // Route by engine: a Parakeet id loaded through the Whisper path
                // simply fails, which is how this was caught.
                if ParakeetModel.isParakeet(e.id) {
                    _ = try await MLEngine.shared.parakeet(version: ParakeetModel.version(for: e.id))
                } else {
                    _ = try await MLEngine.shared.whisperKit(model: e.id, download: true)
                }
                await MainActor.run {
                    prefs.model = e.id
                    downloading = nil
                    catalog.refreshDownloadStates()
                }
            } catch {
                await MainActor.run {
                    downloading = nil
                    // A failed download must leave no partial model behind (FR-18).
                    try? ModelCatalog.removeDownload(e.id)
                    catalog.refreshDownloadStates()
                    downloadError = "The download did not finish: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
