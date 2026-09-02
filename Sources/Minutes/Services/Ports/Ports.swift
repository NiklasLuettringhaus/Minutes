import Foundation

// Ports. Every OS/ML boundary sits behind one of these, implemented in exactly
// one adapter. This is what lets the Heuristic backend be tested without Apple
// Intelligence and the pipeline be tested without audio hardware.

// MARK: - Capture

struct CapturedStreams: Sendable {
    var micURL: URL?
    var systemURL: URL?
    var duration: TimeInterval
    /// False when the tap could not be established or produced only silence (FR-7).
    /// Derived from `systemEvidence`, never from elapsed time (AD-36).
    var systemCaptured: Bool
    /// What each stream can honestly claim about itself. Carried so a caller can
    /// state *why* a stream produced nothing rather than only that it did.
    var micEvidence: AudioEvidence = .none
    var systemEvidence: AudioEvidence = .none
}

protocol Capturing: AnyObject {
    /// Begins capture of both Streams on one session clock (AD-4).
    func start(into directory: URL) throws
    /// Ends capture and returns what was actually captured.
    func stop() -> CapturedStreams
    var isRunning: Bool { get }
    /// Live peak level per Stream, for the Test Playground meters (FR-47).
    func level(for stream: StreamKind) -> Float
}

// MARK: - Transcription

struct TranscribedSegment: Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

protocol Transcribing: Sendable {
    /// Transcribes one audio file. Entirely on-device (NFR-1).
    func transcribe(url: URL, model: String) async throws -> [TranscribedSegment]
}

// MARK: - Diarization

struct DiarizedSpan: Sendable {
    var start: TimeInterval
    var end: TimeInterval
    /// Zero-based speaker index within this stream.
    var speakerIndex: Int
}

protocol Diarizing: Sendable {
    /// Splits ONE stream into per-speaker spans. Never a mixed stream (AD-11).
    func diarize(url: URL) async throws -> [DiarizedSpan]
}

// MARK: - Voice embedding (AD-28)

/// What an embedder reports about one recording.
///
/// It reports rather than judges. Whether two voices in a sample is acceptable is
/// policy, and policy lives in Services — so `VoiceEnrolment` decides to refuse
/// and this type only says what was there.
struct VoiceEmbeddingResult: Sendable {
    /// The dominant speaker's fingerprint — the one who spoke for longest.
    var fingerprint: VoiceFingerprint
    /// How many distinct voices the embedder found. More than one is what makes
    /// an enrolment sample unusable (FR-62).
    var voicesFound: Int
    /// Seconds of actual speech found, not seconds of file. A 25-second recording
    /// of someone thinking is not a 25-second sample.
    var speechSeconds: TimeInterval
    /// The dominant speaker's share of that speech, so "one voice" can be
    /// distinguished from "one voice and a cough".
    var dominantShare: Double
}

/// Turns audio into a comparable fingerprint (AD-28).
///
/// The port exists so the identification path has no Apple dependency. The
/// adapter behind it may have as many as it likes; this signature may have none,
/// and neither may `VoiceMatch`, which does the comparing. If a future
/// implementation is pure Swift DSP or a different model entirely, everything
/// above this line is unaffected — that is the point, and it is the reason the
/// spike rejected Voice Isolation as a mechanism.
protocol VoiceEmbedding: Sendable {
    /// Names what produced a fingerprint, and is stored beside it so a vector is
    /// never compared against one from a different embedder (AD-29).
    var producer: String { get }
    /// Embeds the dominant voice in one audio file. Entirely on-device (NFR-1).
    func embed(url: URL) async throws -> VoiceEmbeddingResult
}

// MARK: - Metadata

protocol MetadataBackend: Sendable {
    var kind: MetadataBackendKind { get }
    /// Whether this backend can run right now. Checked at run time, never assumed
    /// at build time (AD-12).
    func isAvailable() async -> Bool
    func derive(from utterances: [Utterance], names: [String: String]) async throws -> MeetingMetadata
}

// MARK: - Note output

protocol NoteWriting: Sendable {
    /// Renders and atomically writes the Note. Returns the filename it used —
    /// it is the only component that computes one (AD-18).
    func write(meeting: Meeting, into folder: URL) throws -> String
    func render(meeting: Meeting) -> String
}
