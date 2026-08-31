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
    var systemCaptured: Bool
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
    /// Splits ONE stream into per-speaker spans. Only ever called on the System
    /// Stream — never a mixed stream (AD-11).
    func diarize(url: URL) async throws -> [DiarizedSpan]
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
