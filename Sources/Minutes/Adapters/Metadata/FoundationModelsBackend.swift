import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AD-12: preferred when available, never a dependency.
///
/// Apple Intelligence is switched off on the machine this was built for, so the
/// availability check is not defensive boilerplate — it is the expected path, and
/// falling back to the Heuristic backend is normal operation, not an error
/// (AD-17). Uses guided generation into a typed structure rather than parsing
/// free text, so a malformed generation cannot corrupt a Note.
struct FoundationModelsBackend: MetadataBackend {
    let kind: MetadataBackendKind = .foundationModels

    /// Roughly how much transcript we feed the model at once. The real context
    /// limit is undocumented, so long transcripts are summarised in parts and
    /// combined rather than silently truncated (FR-27).
    private static let chunkCharacters = 6000

    func isAvailable() async -> Bool {
        await availability().isUsable
    }

    /// Why the model can or cannot be used — **not** whether (FR-109).
    ///
    /// The reason used to be logged here and discarded, leaving the caller to
    /// invent one. It invented "Apple Intelligence is switched off" and was
    /// wrong on a Mac that had it switched on and was still downloading.
    func availability() async -> LanguageModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                let mapped = Self.map(reason)
                Log.pipeline.info("FoundationModels: \(mapped.summary, privacy: .public)")
                return mapped
            @unknown default:
                return .unrecognised("a state this build does not recognise")
            }
        }
        #endif
        return .unsupportedSystem
    }

    #if canImport(FoundationModels)
    /// The one place a system enum becomes ours. `@unknown default` carries the
    /// system's own description rather than collapsing to a case that would say
    /// something specific and false — which is the bug this whole change is.
    @available(macOS 26.0, *)
    private static func map(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> LanguageModelAvailability {
        switch reason {
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .notEnabled
        case .modelNotReady: return .downloading
        @unknown default: return .unrecognised(String(describing: reason))
        }
    }
    #endif

    func derive(from utterances: [Utterance], names: [String: String]) async throws -> MeetingMetadata {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await generate(utterances: utterances, names: names)
        }
        #endif
        throw MinutesError.stageFailed(stage: "Metadata", reason: "The on-device language model is not available.")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func generate(utterances: [Utterance], names: [String: String]) async throws -> MeetingMetadata {
        let transcript = Self.plainTranscript(utterances: utterances, names: names)
        let chunks = Self.chunk(transcript, limit: Self.chunkCharacters)

        // Long transcript: reduce each part, then summarise the reduction.
        var working = transcript
        if chunks.count > 1 {
            var partials: [String] = []
            for c in chunks {
                let s = try await Self.summarisePart(c)
                partials.append(s)
            }
            working = partials.joined(separator: "\n")
        }

        let session = LanguageModelSession(instructions: """
            You summarise meeting transcripts. Be factual and terse. Never invent \
            content: if the transcript contains no decisions or no action items, \
            return empty lists. Use the speaker names exactly as they appear.
            """)
        let prompt = """
            Summarise this meeting.

            \(working)
            """
        let response = try await session.respond(to: prompt, generating: MeetingBrief.self)
        let brief = response.content

        return MeetingMetadata(
            title: brief.title.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: brief.tags.prefix(6).map { $0.lowercased().replacingOccurrences(of: " ", with: "-") },
            summary: brief.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            decisions: brief.decisions.map { Decision(text: $0, at: nil) },
            actionItems: brief.actionItems.map {
                ActionItem(text: $0.task, owner: $0.owner?.isEmpty == false ? $0.owner : nil, at: nil)
            },
            backend: .foundationModels)
    }

    @available(macOS 26.0, *)
    private static func summarisePart(_ part: String) async throws -> String {
        let session = LanguageModelSession(instructions:
            "Condense this portion of a meeting transcript into its key points. Be factual and terse.")
        let r = try await session.respond(to: part)
        return r.content
    }
    #endif

    // MARK: - Transcript shaping

    static func plainTranscript(utterances: [Utterance], names: [String: String]) -> String {
        var out: [String] = []
        var last: String? = nil
        var buffer: [String] = []
        func flush() {
            if let l = last, !buffer.isEmpty { out.append("\(l): \(buffer.joined(separator: " "))") }
            buffer = []
        }
        for u in utterances.sorted(by: { $0.start < $1.start }) {
            let who = names[u.speaker.raw] ?? (u.speaker.isLocal ? "Me" : "Speaker")
            if who != last { flush(); last = who }
            buffer.append(u.text)
        }
        flush()
        return out.joined(separator: "\n")
    }

    static func chunk(_ s: String, limit: Int) -> [String] {
        guard s.count > limit else { return [s] }
        var out: [String] = []
        var cur = ""
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            if cur.count + line.count + 1 > limit, !cur.isEmpty {
                out.append(cur); cur = ""
            }
            cur += (cur.isEmpty ? "" : "\n") + line
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

#if canImport(FoundationModels)
/// Guided-generation schema. Typed output means a malformed generation cannot
/// corrupt a Note (FR-27).
@available(macOS 26.0, *)
@Generable
struct MeetingBrief {
    @Guide(description: "A short specific title for the meeting, 3 to 8 words. No date, no quotes.")
    var title: String

    @Guide(description: "Three to six lowercase topic tags, single words or short hyphenated phrases.")
    var tags: [String]

    @Guide(description: "Two to four sentences summarising what the meeting was about and what came of it.")
    var summary: String

    @Guide(description: "Decisions actually agreed in the meeting. Empty if none were agreed.")
    var decisions: [String]

    @Guide(description: "Concrete commitments someone made. Empty if none were made.")
    var actionItems: [BriefAction]
}

@available(macOS 26.0, *)
@Generable
struct BriefAction {
    @Guide(description: "What needs doing, one sentence.")
    var task: String
    @Guide(description: "Who owns it, exactly as named in the transcript. Empty string if the transcript does not say.")
    var owner: String?
}
#endif
