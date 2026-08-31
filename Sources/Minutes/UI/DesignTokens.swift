import SwiftUI

/// The DESIGN.md token set, in code.
///
/// Almost every colour here resolves from AppKit semantic colours at render time.
/// That is the rule that makes light mode, dark mode and Increase Contrast work
/// without a single conditional — and it is why only three literal colours exist.
enum Tok {

    // MARK: - Colours

    /// Platform-owned. Never hardcoded.
    static let surfaceWindow = Color(nsColor: .windowBackgroundColor)
    static let surfaceCard   = Color(nsColor: .controlBackgroundColor)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let separator     = Color(nsColor: .separatorColor)
    /// The **user's** system accent. Standard controls keep it; do not repaint
    /// them with brand teal.
    static let controlAccent = Color.accentColor

    /// Literal, because macOS provides no semantic equivalent and the meaning is
    /// non-negotiable. Recording red appears nowhere else in the product —
    /// reserving it is what makes a red menu bar icon legible at a glance.
    static let recording    = Color(red: 0.898, green: 0.282, blue: 0.302)  // #E5484D
    static let transcribing = Color(red: 0.961, green: 0.647, blue: 0.141)  // #F5A524
    /// Cold on purpose: it can never be mistaken for the Recording state, which a
    /// warm accent could be.
    static let brand        = Color(red: 0.071, green: 0.647, blue: 0.580)  // #12A594
    /// Readable amber for text on a light ground (the raw amber is too pale).
    static let amberInk     = Color(red: 0.604, green: 0.384, blue: 0.012)

    // MARK: - Radii

    static let rSm: CGFloat = 4
    static let rMd: CGFloat = 6
    static let rLg: CGFloat = 10

    // MARK: - Spacing

    static let s2: CGFloat = 4
    static let s3: CGFloat = 8
    static let s4: CGFloat = 12
    static let s5: CGFloat = 16
    static let s6: CGFloat = 20
    static let s7: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 16
    static let paneMargin: CGFloat = 20
}

// MARK: - Card

/// Tonal separation only: no shadow, no border. A stroke on top of a tonal step
/// reads heavier than macOS does, and a drop shadow on a settings card is the
/// most reliable tell of a non-native Mac app.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(Tok.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tok.surfaceCard, in: RoundedRectangle(cornerRadius: Tok.rLg))
    }
}

/// Headings sit **outside** the card, which is what makes a pane scannable by
/// heading alone.
struct SectionHeading: View {
    let text: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(text).font(.headline)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, Tok.s3)
    }
}

// MARK: - Done pill

/// Deliberately **not** a button: no border, no hover state, not focusable, fully
/// round so it reads as status. If a user tries to click it, the design has failed.
struct DonePill: View {
    var body: some View {
        HStack(spacing: Tok.s2) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            Text("Done").font(.caption)
        }
        .foregroundStyle(Tok.brand)
        .padding(.horizontal, Tok.s4)
        .padding(.vertical, Tok.s2 + 1)
        .background(Tok.brand.opacity(0.15), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel("Done")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Checklist row

/// The borrowed pattern (FR-46). Anatomy: leading indicator, title over a
/// one-line subtitle, trailing control. Satisfied rows recede so the eye lands
/// on outstanding work — a user opening Setup should see what is left to do, not
/// a wall of green.
struct ChecklistRow<Trailing: View>: View {
    let ordinal: Int
    let title: String
    let subtitle: String
    let isSatisfied: Bool
    var isOptional: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Tok.s4) {
            indicator
                .frame(width: 19, height: 19)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Tok.s2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(isSatisfied ? .regular : .medium)
                        .foregroundStyle(isSatisfied ? Tok.textSecondary : Tok.textPrimary)
                    if isOptional {
                        Text("· optional").font(.caption2).foregroundStyle(Tok.textSecondary)
                    }
                }
                // Never omitted, never longer than a line. If it needs two lines,
                // the copy is wrong.
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Tok.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Tok.s4)
            trailing
        }
        .padding(.vertical, 11)
        .opacity(isSatisfied ? 0.55 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isSatisfied ? "done" : "outstanding"). \(subtitle)")
    }

    @ViewBuilder private var indicator: some View {
        if isSatisfied {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Tok.brand)
        } else {
            Text("\(ordinal)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Tok.textSecondary)
                .frame(width: 19, height: 19)
                .overlay(Circle().strokeBorder(Tok.separator, lineWidth: 1.4))
        }
    }
}

/// The one interactive control in an outstanding row.
struct RowActionButton: View {
    let title: String
    var showsChevron: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                if showsChevron { Text("→") }
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(Tok.brand)
        .controlSize(.small)
    }
}

/// Hairline between rows, inset to the text origin, none after the last.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Tok.separator)
            .frame(height: 1)
            .padding(.leading, 19 + Tok.s4)
    }
}

// MARK: - State banner

/// How Recording, Transcribing and degraded capture are announced in the window.
/// The degraded variant carries a warning glyph, because degradation is never
/// silent (FR-7).
struct StateBanner: View {
    enum Kind { case recording, transcribing, degraded, info }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: Tok.s3) {
            Image(systemName: glyph).font(.caption)
            Text(text).font(.caption)
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Tok.s4)
        .padding(.vertical, Tok.s3)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Tok.rMd))
    }

    private var tint: Color {
        switch kind {
        case .recording: return Tok.recording
        case .transcribing, .degraded: return Tok.transcribing
        case .info: return Tok.brand
        }
    }
    private var glyph: String {
        switch kind {
        case .recording: return "record.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .degraded: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
}

// MARK: - Speaker chip

/// The Local Speaker is brand-tinted and Remote Speakers are neutral. This single
/// visual difference encodes the product's structural claim: one of these labels
/// is a fact, the others are inferences.
struct SpeakerChip: View {
    let name: String
    /// Where the voice was. This is the structural fact; who it is may not be.
    let place: SpeakerLabelID.Place
    var isInferred: Bool = false

    /// Convenience for call sites that only know local-or-not.
    init(name: String, isLocal: Bool, isInferred: Bool = false) {
        self.name = name
        self.place = isLocal ? .you : .remote
        self.isInferred = isInferred
    }
    init(name: String, place: SpeakerLabelID.Place, isInferred: Bool = false) {
        self.name = name; self.place = place; self.isInferred = isInferred
    }

    var body: some View {
        HStack(spacing: 4) {
            if place == .room {
                Image(systemName: "person.2.fill").font(.system(size: 8))
            }
            Text(isInferred ? "~\(name)" : name)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, Tok.s3)
        .padding(.vertical, 2)
        .background(background, in: Capsule())
        .help(helpText)
    }

    private var tint: Color {
        switch place {
        case .you:    return Tok.brand
        case .room:   return Tok.amberInk
        case .remote: return Tok.textSecondary
        }
    }
    private var background: Color {
        switch place {
        case .you:    return Tok.brand.opacity(0.15)
        case .room:   return Tok.transcribing.opacity(0.16)
        case .remote: return Tok.separator.opacity(0.5)
        }
    }
    private var helpText: String {
        if isInferred { return "Recognised from a previous meeting — check it is right." }
        switch place {
        case .you:    return "You. The microphone held a single voice, so this is certain."
        case .room:   return "Someone in the room with you. Minutes knows the voice was in the room, but not who it is — rename it once and it will be recognised next time."
        case .remote: return "A participant on the other end of the call."
        }
    }
}

// MARK: - Level meter

/// Per-Stream meters are the Test Playground's actual diagnostic: a flat System
/// meter is the answer to "is system audio working?".
struct LevelMeter: View {
    let label: String
    let level: Float
    let status: String?
    var statusOK: Bool = true

    var body: some View {
        HStack(spacing: Tok.s3) {
            Text(label).font(.caption).frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tok.separator)
                    Capsule().fill(Tok.brand)
                        .frame(width: max(0, min(1, CGFloat(level) * 2.5)) * geo.size.width)
                }
            }
            .frame(height: 5)
            if let status {
                Text(status)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(statusOK ? Tok.brand : Tok.recording)
                    .frame(width: 76, alignment: .trailing)
            }
        }
    }
}

// MARK: - Fact chips

struct FactChip: View {
    let text: String
    var good: Bool = false
    var body: some View {
        Text(text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(good ? Tok.brand : Tok.textSecondary)
            .padding(.horizontal, Tok.s3)
            .padding(.vertical, 3)
            .background((good ? Tok.brand.opacity(0.14) : Tok.separator.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: Tok.rSm))
    }
}
