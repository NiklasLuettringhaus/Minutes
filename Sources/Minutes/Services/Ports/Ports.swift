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
    /// Whether each stream's samples are at the rate it claimed (AD-45).
    ///
    /// Per stream, not per Meeting. In all seven observed failures the microphone
    /// was correct and the system stream was not, so one flag for the recording
    /// would have been wrong in both directions.
    var micRate: RateFidelity = .unknown
    var systemRate: RateFidelity = .unknown
    /// Whether the tap was actually established. Distinguishes "the tap failed to
    /// start", which reported itself at start, from "the tap ran and heard
    /// nothing", which is the condition worth telling the user about — including
    /// when it delivered no callbacks at all and so has zero duration.
    var systemTapEstablished: Bool = false
    /// Whether each stream received everything its device produced (AD-51).
    var micContinuity: StreamContinuity = .unknown
    var systemContinuity: StreamContinuity = .unknown
    /// Seconds to add to a System Stream time to place it on the Mic Stream's
    /// timeline (FR-97, AD-53).
    ///
    /// The difference between the two Streams' first-sample host times, on one
    /// system-wide clock. `nil` where either device supplied no timestamp — and
    /// `nil` means unknown, never zero: a Meeting whose offset was never measured
    /// must not be silently re-ordered by a guess.
    var streamStartOffset: TimeInterval?
    /// What the audio was playing through, and therefore whether Echo was even
    /// possible (FR-98, AD-54). `nil` where nothing could be read.
    var outputDevice: OutputDevice?
    /// Whether the output changed kind mid-Session. Recorded because the union
    /// in `outputDevice.kind` deliberately hides *when* it was possible.
    var outputDeviceChanged: Bool = false
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
    /// Renders and atomically writes the Note.
    ///
    /// `at` is the file the Note Link resolved to, when one was found. Passing it
    /// is how a rewrite stops deriving a destination from a stored filename it has
    /// not checked — the defect that turned a renamed Note into a permanently
    /// orphaned duplicate (FR-35 as amended).
    ///
    /// Returns an outcome rather than a filename, because refusing to overwrite
    /// bytes the app did not write is a result the caller must handle (FR-81).
    func write(meeting: Meeting, into folder: URL, at located: URL?) throws -> NoteWriteOutcome
    func render(meeting: Meeting) -> String
}

/// What a Note write actually did. AD-41.
///
/// The refusal is a return value and not a thrown error on purpose: `throws`
/// invites the `try?` that would discard it, and `Pipeline.rewriteNote` already
/// logs-and-swallows its errors.
enum NoteWriteOutcome: Equatable, Sendable {
    /// `filename` is the name on disk — which may be the user's, not the app's.
    /// `written` is the name the app would have chosen, stored so that a later
    /// divergence between the two identifies a user rename (AD-40).
    case wrote(filename: String, written: String, digest: String)
    /// The file on disk is not the bytes Minutes last wrote. Nothing was written.
    case refusedChangedOnDisk(URL)
}

// MARK: - Note location (AD-39)

/// Where a Meeting's Note actually is.
enum NoteLocation: Equatable, Sendable {
    case located(URL)
    /// More than one file claims this Meeting. Reported, never guessed — picking
    /// one means the next rewrite destroys the other.
    case ambiguous([URL])
    case notFound
}

/// A file in the Notes Folder that Minutes wrote and no Meeting claims (FR-82).
///
/// Carries only what its own frontmatter says, because that is all there is: the
/// Meeting it belonged to is gone, and a Note cannot be parsed back into one.
struct UnclaimedNote: Equatable, Sendable, Identifiable {
    let url: URL
    let startedAt: Date?
    var id: String { url.path }
    var filename: String { url.lastPathComponent }
}

/// AD-39: resolving a Note Link. Reads frontmatter identity only, and creates,
/// renames, moves and deletes nothing.
protocol NoteLocating: Sendable {
    func locate(meeting: Meeting, in folder: URL) throws -> NoteLocation
    func unclaimed(meetings: [Meeting], in folder: URL) throws -> [UnclaimedNote]
}

// MARK: - What one Stream's capture reports (AD-51)

/// Everything a single Stream's capture can say about itself when it stops.
///
/// Introduced in increment 10 to replace a five-element tuple that was about to
/// become a seven-element one. Both capture adapters return this; `CapturedStreams`
/// is the pair of them plus what only the pair can say.
struct StreamCaptureResult: Sendable {
    var duration: TimeInterval = 0
    var evidence: AudioEvidence = .none
    /// Whether the samples are at the rate the stream claimed (AD-44, AD-51).
    var rate: RateFidelity = .unknown
    /// Whether the app received everything the device produced (AD-51).
    var continuity: StreamContinuity = .unknown
    /// Host time, in seconds, of the very first sample this Stream delivered.
    /// The two Streams' offset is the difference of these (FR-97, AD-53).
    var originHostSeconds: Double?
}
