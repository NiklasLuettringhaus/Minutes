import Foundation

/// What build this is. AD-33: the values come from the git tag and are written
/// into the bundle when it is assembled, so nothing here is maintained by hand.
///
/// A development build is labelled as one rather than inheriting the last
/// release's number — an ambiguous version makes every bug report ambiguous too.
enum AppVersion {
    private static func string(_ key: String) -> String? {
        Bundle.main.infoDictionary?[key] as? String
    }

    /// e.g. `0.1.0`.
    static var short: String { string("CFBundleShortVersionString") ?? "unknown" }

    /// Commit count. Monotonic across releases.
    static var build: String { string("CFBundleVersion") ?? "0" }

    /// `git describe` output — the exact commit, and whether the tree was dirty.
    static var describe: String { string("MinutesGitDescribe") ?? "unknown" }

    /// True only when the bundle was built from an exact, clean tag.
    static var isRelease: Bool { Bundle.main.infoDictionary?["MinutesIsRelease"] as? Bool ?? false }

    /// One line for a bug report or an About row.
    static var display: String {
        isRelease ? "\(short) (\(build))" : "\(short) (\(build)) · \(describe) · development build"
    }
}
