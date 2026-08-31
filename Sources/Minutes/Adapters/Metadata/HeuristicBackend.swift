import Foundation

/// AD-12: the floor. Pure, deterministic, dependency-free, always available.
///
/// This is not a stub. Apple Intelligence is off on the target machine, so this
/// is the backend that actually titles meetings there. It is also the unit-test
/// target precisely because it is deterministic.
struct HeuristicBackend: MetadataBackend {
    let kind: MetadataBackendKind = .heuristic

    /// No model, no network, no assets — always true.
    func isAvailable() async -> Bool { true }

    /// FR-55: this Backend produces a title and tags, and deliberately **no**
    /// summary, decisions or action items.
    ///
    /// It used to produce all five. The "summary" was the four highest-weighted
    /// sentences of the transcript, in transcript order — which for a short meeting
    /// came to roughly 80% of the original text and read convincingly enough to be
    /// mistaken for a summary. §9.3 requires that absence be represented honestly
    /// rather than as invented content, and a persuasive extract of someone else's
    /// words is closer to invention than to absence.
    ///
    /// Titles and tags stay because they are observably good: "Pricing Page",
    /// "Page Redesigned Together". Keyphrase salience is the right tool for a short
    /// label and the wrong tool for prose.
    ///
    /// `Self.summary`, `Self.decisions` and `Self.actionItems` are retained,
    /// unused, and still unit-tested — they are pure functions and the only tested
    /// implementation of extractive metadata. Re-enabling any of them is a one-line
    /// change here, which matters because the action-item extraction was the
    /// best-performing part of the three.
    func derive(from utterances: [Utterance], names: [String: String]) async throws -> MeetingMetadata {
        let sentences = Self.sentences(from: utterances)
        let phrases = Self.keyphrases(in: sentences)

        return MeetingMetadata(
            title: Self.title(from: sentences, phrases: phrases),
            tags: Self.tags(from: phrases),
            summary: "",
            decisions: [],
            actionItems: [],
            backend: .heuristic)
    }

    // MARK: - Sentence model

    struct Sentence {
        var text: String
        var at: TimeInterval
        var speaker: SpeakerLabelID
        /// 0.0 at the start of the meeting, 1.0 at the end.
        var position: Double
        var words: [String]
    }

    static func sentences(from utterances: [Utterance]) -> [Sentence] {
        let total = utterances.last?.end ?? 1
        var out: [Sentence] = []
        for u in utterances {
            for raw in splitSentences(u.text) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard t.count > 2 else { continue }
                out.append(Sentence(
                    text: t, at: u.start, speaker: u.speaker,
                    position: total > 0 ? min(1, max(0, u.start / total)) : 0,
                    words: words(in: t)))
            }
        }
        return out
    }

    static func splitSentences(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""
        for ch in s {
            cur.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                out.append(cur); cur = ""
            }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    static func words(in s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Keyphrase extraction

    /// Stopwords plus conversational filler. Meeting speech is full of words that
    /// are frequent and meaningless, and a tag list of "yeah, think, kind" is worse
    /// than no tags.
    static let stop: Set<String> = [
        "a","an","the","and","or","but","if","then","so","because","as","of","at","by","for","with",
        "about","into","through","during","to","from","up","down","in","out","on","off","over","under",
        "again","further","once","here","there","when","where","why","how","all","any","both","each",
        "few","more","most","other","some","such","no","nor","not","only","own","same","than","too",
        "very","can","will","just","should","now","i","me","my","we","our","you","your","he","him",
        "his","she","her","it","its","they","them","their","this","that","these","those","am","is",
        "are","was","were","be","been","being","have","has","had","do","does","did","doing","would",
        "could","shall","may","might","must","ok","okay","yeah","yes","no","right","like","kind",
        "sort","really","actually","basically","literally","think","know","mean","going","get","got",
        "gonna","wanna","sure","well","said","say","says","lot","bit","thing","things","stuff","one",
        "two","also","maybe","perhaps","let","lets","us","hey","hi","hello","thanks","thank","cool",
        "great","nice","good","bad","much","many","make","makes","made","see","look","looking","want",
        "need","needs","time","times","day","days","week","weeks","today","tomorrow","yesterday",
        "guys","everyone","anyone","somebody","someone","anything","something","nothing","because",
        "guess","suppose","probably","definitely","totally","obviously","essentially","um","uh","er",
    ]

    struct Phrase { var text: String; var score: Double; var count: Int }

    /// Scores 1-3 word n-grams by frequency, length preference, and early-position
    /// weighting. Deterministic: ties broken alphabetically.
    static func keyphrases(in sentences: [Sentence]) -> [Phrase] {
        var counts: [String: Int] = [:]
        var earliest: [String: Double] = [:]

        for s in sentences {
            let ws = s.words
            for n in 1...3 where ws.count >= n {
                for i in 0...(ws.count - n) {
                    let gram = Array(ws[i..<(i + n)])
                    // Reject grams that start or end on a stopword, or are entirely stopwords.
                    guard let f = gram.first, let l = gram.last,
                          !stop.contains(f), !stop.contains(l),
                          gram.contains(where: { !stop.contains($0) }),
                          gram.allSatisfy({ $0.count > 2 })
                    else { continue }
                    let key = gram.joined(separator: " ")
                    counts[key, default: 0] += 1
                    earliest[key] = min(earliest[key] ?? 1, s.position)
                }
            }
        }

        return counts.compactMap { key, c -> Phrase? in
            guard c >= 2 || key.contains(" ") else { return nil }
            let n = Double(key.split(separator: " ").count)
            let early = 1.0 - (earliest[key] ?? 0.5) * 0.35
            // Multi-word phrases are more informative than single words at equal frequency.
            let score = Double(c) * pow(n, 1.4) * early
            return Phrase(text: key, score: score, count: c)
        }
        .sorted { a, b in a.score == b.score ? a.text < b.text : a.score > b.score }
    }

    /// Drops phrases contained in a higher-scoring one ("pricing page" beats "pricing").
    static func dedupe(_ phrases: [Phrase], limit: Int) -> [Phrase] {
        var kept: [Phrase] = []
        for p in phrases {
            if kept.contains(where: { $0.text.contains(p.text) || p.text.contains($0.text) }) { continue }
            kept.append(p)
            if kept.count == limit { break }
        }
        return kept
    }

    // MARK: - Derived fields

    static func tags(from phrases: [Phrase]) -> [String] {
        let top: [Phrase] = dedupe(phrases, limit: 6)
        var out: [String] = []
        for p in top where p.count >= 2 {
            out.append(p.text.replacingOccurrences(of: " ", with: "-"))
            if out.count == 6 { break }
        }
        return out
    }

    static func title(from sentences: [Sentence], phrases: [Phrase]) -> String {
        // Prefer a phrase that appears in the first third — meetings usually state
        // their subject early — and prefer multi-word phrases.
        var early = Set<String>()
        for s in sentences where s.position <= 0.34 { early.formUnion(s.words) }

        let candidates: [Phrase] = dedupe(phrases, limit: 12)
        var scored: [(phrase: Phrase, score: Double)] = []
        for p in candidates {
            let parts: [String] = p.text.split(separator: " ").map(String.init)
            var allEarly = true
            for w in parts where !early.contains(w) { allEarly = false }
            let boost: Double = allEarly ? 1.6 : 1.0
            scored.append((p, p.score * boost))
        }
        scored.sort { a, b in a.score == b.score ? a.phrase.text < b.phrase.text : a.score > b.score }

        guard let best = scored.first?.phrase else { return "" }
        var words: [String] = []
        for w in best.text.split(separator: " ") {
            words.append(w.prefix(1).uppercased() + w.dropFirst())
        }
        return words.joined(separator: " ")
    }

    static func summary(from sentences: [Sentence], phrases: [Phrase], limit: Int = 4) -> String {
        guard !sentences.isEmpty else { return "" }

        var weights: [String: Double] = [:]
        for p in phrases { weights[p.text] = max(weights[p.text] ?? 0, p.score) }
        let maxScore: Double = phrases.first?.score ?? 1.0

        var scored: [(index: Int, score: Double)] = []
        for (i, s) in sentences.enumerated() {
            let lower: String = s.text.lowercased()
            var score: Double = 0
            for (phrase, w) in weights {
                if lower.contains(phrase) { score += w / maxScore }
            }
            // Normalise by length so long rambles do not win on volume alone,
            // and mildly favour the opening where the subject is usually stated.
            let lengthNorm: Double = max(4.0, Double(s.words.count))
            let positionBoost: Double = 1.0 + (1.0 - s.position) * 0.25
            score = score / lengthNorm.squareRoot() * positionBoost
            // Very short or very long sentences make poor summary lines.
            if s.words.count < 5 || s.words.count > 45 { score *= 0.25 }
            scored.append((i, score))
        }

        scored.sort { a, b in a.score == b.score ? a.index < b.index : a.score > b.score }
        var picked: [Int] = []
        for entry in scored.prefix(limit) { picked.append(entry.index) }
        picked.sort()

        var parts: [String] = []
        for i in picked { parts.append(sentences[i].text) }
        return parts.joined(separator: " ")
    }

    // MARK: - Cue-phrase extraction

    static let decisionCues = [
        "we decided", "we've decided", "we agreed", "let's go with", "we'll go with",
        "the plan is", "we're going with", "decision is", "we settled on", "final answer",
        "agreed that", "so we'll", "we will go", "it's decided",
    ]

    static let actionCues = [
        "i'll ", "i will ", "action item", "can you ", "could you ", "please ",
        "we need to ", "needs to ", "take care of", "follow up", "let me ",
        "i'm going to ", "will handle", "will take", "assigned to", "owner is",
    ]

    static func decisions(in sentences: [Sentence]) -> [Decision] {
        var out: [Decision] = []
        for s in sentences {
            let l = s.text.lowercased()
            guard decisionCues.contains(where: { l.contains($0) }) else { continue }
            out.append(Decision(text: clean(s.text), at: s.at))
            if out.count == 8 { break }
        }
        return out
    }

    static func actionItems(in sentences: [Sentence], names: [String: String]) -> [ActionItem] {
        var out: [ActionItem] = []
        for s in sentences {
            let l = s.text.lowercased()
            guard let cue = actionCues.first(where: { l.contains($0) }) else { continue }
            // First person cue => the speaker owns it. Otherwise leave the owner
            // unset rather than guess (FR-29: omit the owner where not identified).
            var owner: String? = nil
            if cue.hasPrefix("i'll") || cue.hasPrefix("i will") || cue.hasPrefix("i'm going to") || cue.hasPrefix("let me") {
                owner = names[s.speaker.raw]
            } else if let named = names.values.first(where: { l.contains($0.lowercased()) && $0.count > 2 }) {
                owner = named
            }
            out.append(ActionItem(text: clean(s.text), owner: owner, at: s.at))
            if out.count == 12 { break }
        }
        return out
    }

    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let f = t.first, f == "," || f == "-" || f == "–" { t.removeFirst() }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
