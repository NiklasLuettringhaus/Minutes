import SwiftUI

/// FR-17 / FR-18. The list comes from the library at run time (AD-13) — the
/// published docs list bare names like `base`, but the real identifiers are
/// `openai_whisper-`-prefixed, so a hardcoded list would offer models that do
/// not exist.
struct TranscriptionPane: View {
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var catalog = ModelCatalog.shared
    @State private var downloading: String?
    @State private var downloadError: String?

    var body: some View {
        PaneScaffold(title: "Transcription",
                     subtitle: "Which model turns your meetings into text. Everything runs on this Mac.") {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(text: "Model", trailing: AnyView(
                    Group {
                        if catalog.isRefreshing { ProgressView().controlSize(.small) }
                        else {
                            Button("Refresh list") { Task { await catalog.refreshFromNetwork() } }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                ))
                Card {
                    ForEach(Array(catalog.entries.enumerated()), id: \.element.id) { idx, e in
                        modelRow(e)
                        if idx < catalog.entries.count - 1 { RowDivider() }
                    }
                    if catalog.entries.isEmpty {
                        Text("No models listed yet.").font(.caption).foregroundStyle(Tok.textSecondary)
                    }
                }
            }

            if let downloadError {
                StateBanner(kind: .degraded, text: downloadError)
            }

            Card {
                VStack(alignment: .leading, spacing: Tok.s3) {
                    // Stated once, plainly (FR-18).
                    Text("Downloading a model is the only time Minutes uses the network.")
                        .font(.caption).foregroundStyle(Tok.textSecondary)
                    if catalog.offlineOnly {
                        Text("Showing the models recommended for this Mac. Refresh to see the full catalogue.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                    }
                    if let r = prefs.lastThroughputRatio, r > 0 {
                        Text(String(format: "Measured on this Mac: %.2f s of processing per second of audio.", r))
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                    } else {
                        Text("Speed figures below are estimates. Run the test in Getting Started to measure your Mac.")
                            .font(.caption).foregroundStyle(Tok.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            if catalog.entries.isEmpty { catalog.loadLocalRecommendations() }
            catalog.refreshDownloadStates()
        }
    }

    private func modelRow(_ e: ModelCatalog.Entry) -> some View {
        let isActive = e.id == prefs.model
        return HStack(alignment: .center, spacing: Tok.s4) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Tok.brand : Tok.textSecondary)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Tok.s3) {
                    Text(e.displayName).font(.body)
                        .fontWeight(isActive ? .medium : .regular)
                    if e.id == Preferences.defaultModel {
                        Text("recommended").font(.caption2).foregroundStyle(Tok.brand)
                    }
                }
                Text(subtitle(e)).font(.caption).foregroundStyle(Tok.textSecondary)
            }
            Spacer(minLength: Tok.s4)
            trailing(e, isActive: isActive)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { select(e) }
    }

    private func subtitle(_ e: ModelCatalog.Entry) -> String {
        var parts = ["\(e.speed.rawValue) · \(e.accuracy.rawValue) accuracy"]
        if let b = e.approxBytes { parts.append(Fmt.bytes(b)) }
        else if e.isDownloaded { parts.append(Fmt.bytes(ModelCatalog.bytesOnDisk(e.id))) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailing(_ e: ModelCatalog.Entry, isActive: Bool) -> some View {
        if downloading == e.id {
            // Determinate where possible; WhisperKit reports coarse progress, so
            // this stays a visible activity indicator with a label rather than a
            // bare spinner.
            HStack(spacing: Tok.s3) {
                ProgressView().controlSize(.small)
                Text("Downloading…").font(.caption).foregroundStyle(Tok.textSecondary)
            }
        } else if e.isDownloaded {
            HStack(spacing: Tok.s3) {
                Text("Downloaded").font(.caption).foregroundStyle(Tok.textSecondary)
                if !isActive {
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

    /// Selecting an undownloaded model starts its download and makes it active on
    /// completion, not before (FR-18).
    private func select(_ e: ModelCatalog.Entry) {
        downloadError = nil
        if e.isDownloaded {
            prefs.model = e.id
            return
        }
        guard downloading == nil else { return }
        downloading = e.id
        Task {
            do {
                _ = try await MLEngine.shared.whisperKit(model: e.id, download: true)
                await MainActor.run {
                    prefs.model = e.id
                    downloading = nil
                    catalog.refreshDownloadStates()
                }
            } catch {
                await MainActor.run {
                    downloading = nil
                    // A failed download must leave no partial model that could
                    // later load as valid (FR-18).
                    try? ModelCatalog.removeDownload(e.id)
                    catalog.refreshDownloadStates()
                    downloadError = "The download did not finish: \(error.localizedDescription)"
                }
            }
        }
    }
}
