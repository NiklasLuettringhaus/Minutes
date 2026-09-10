import Foundation

/// Why the on-device language model can or cannot be used (FR-109, AD-12).
///
/// **This exists because a `Bool` was carrying it.** `FoundationModelsBackend`
/// answered `isAvailable() -> Bool`, logged the reason and threw it away, and the
/// Summaries pane then told the user the one reason it had guessed: *"Apple
/// Intelligence is switched off on this Mac."* On a Mac where Apple Intelligence
/// was switched **on** and still downloading its models, that sentence was
/// simply false, and it sent the user to a setting they had already changed.
///
/// It is the same defect as `RingBuffer.didOverflow`, which increment 11
/// replaced for the same reason: a Bool cannot distinguish causes, so whoever
/// reads it has to invent one.
///
/// Pure and Foundation-only, with no `FoundationModels` import, so every case
/// below is testable on any machine — including the cases this Mac cannot
/// produce, which are exactly the ones a developer never sees and a user does.
enum LanguageModelAvailability: Equatable, Sendable {

    /// The model is there and can be asked for a summary.
    case available

    /// Apple Intelligence is switched off. The one case the old message assumed.
    case notEnabled

    /// Switched on; macOS has not finished downloading the models.
    ///
    /// **The case that produced this type.** It is temporary, it is nobody's
    /// mistake, and it is not a setting to change — so telling the user to go and
    /// switch something on is worse than saying nothing.
    case downloading

    /// This Mac cannot run it at all.
    case deviceNotEligible

    /// The framework or the OS version this build needs is not present.
    case unsupportedSystem

    /// A reason this build has no text for. Carries what the system said so the
    /// log and `--doctor` can repeat it verbatim rather than flatten it.
    case unrecognised(String)

    var isUsable: Bool { self == .available }

    /// Whether this can become `available` while the app keeps running, so the
    /// answer is worth asking for again rather than being settled.
    var mayResolveItself: Bool {
        switch self {
        case .downloading, .notEnabled: return true
        case .available, .deviceNotEligible, .unsupportedSystem, .unrecognised: return false
        }
    }

    /// Whether opening System Settings could plausibly change this. False where
    /// it cannot, because a button that changes nothing is worse than no button.
    var settingsCanHelp: Bool {
        switch self {
        case .notEnabled, .downloading, .unrecognised: return true
        case .available, .deviceNotEligible, .unsupportedSystem: return false
        }
    }

    /// One line, for `--doctor` and the log.
    var summary: String {
        switch self {
        case .available: return "available"
        case .notEnabled: return "Apple Intelligence is switched off"
        case .downloading: return "switched on; macOS is still downloading the models"
        case .deviceNotEligible: return "this Mac cannot run Apple Intelligence"
        case .unsupportedSystem: return "this build of macOS has no on-device model"
        case .unrecognised(let why): return "unavailable: \(why)"
        }
    }

    /// What the user is told. Each case says what is true of *that* case and
    /// nothing more — the whole point of the type.
    var reasonForUser: String {
        switch self {
        case .available:
            return "Apple Intelligence is on, so titles, summaries, decisions and action items are written by the model built into macOS. It runs on this Mac."
        case .notEnabled:
            return "Apple Intelligence is switched off on this Mac, so there is no language model to use."
        case .downloading:
            return "Apple Intelligence is on, but macOS has not finished downloading its models yet. Nothing is wrong and there is nothing to change — this will start working on its own once the download completes."
        case .deviceNotEligible:
            return "This Mac cannot run Apple Intelligence, so there is no language model to use."
        case .unsupportedSystem:
            return "This version of macOS has no on-device language model, so there is none to use."
        case .unrecognised(let why):
            return "macOS says the on-device language model is unavailable (\(why)). Apple Intelligence settings will say why — a managed Mac can restrict it."
        }
    }

    /// The sentence that is true in every unavailable case and belongs after the
    /// reason, kept apart from it so a changed reason cannot make it wrong.
    static let fallbackDescription = "Titles and summaries are built by selecting the most salient sentences and phrases from the transcript — the same transcript always gives the same result. Nothing is invented: every decision and action item cites the timestamp it came from."
}
