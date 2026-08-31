import Foundation

/// Where downloaded models live.
///
/// This is set explicitly rather than left to the library's default, for two
/// reasons found by inspecting a real download: the default is
/// `~/Documents/huggingface/`, which (a) dumps hundreds of megabytes into the
/// user's Documents folder, and (b) made "is the model downloaded?" depend on
/// matching an internal implementation detail. Owning the path makes the
/// checklist row correct by construction instead of by coincidence.
enum ModelStorage {
    /// `~/Library/Application Support/Minutes/models`
    static var base: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = support.appendingPathComponent("Minutes/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Where WhisperKit places a given variant under `base`.
    static func whisperFolder(_ variant: String) -> URL {
        base.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
    }

    /// The library's own default, kept only so an existing download can be
    /// adopted instead of re-fetched.
    private static var legacyBase: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    /// Moves any models the library already downloaded into our location, so
    /// changing the base does not cost the user a second 600 MB download.
    /// Idempotent and best-effort.
    static func adoptLegacyDownloads() {
        let fm = FileManager.default
        guard let legacy = legacyBase,
              fm.fileExists(atPath: legacy.path) else { return }
        let destRoot = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let srcRoot = legacy.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        guard fm.fileExists(atPath: srcRoot.path) else { return }
        try? fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
        guard let variants = try? fm.contentsOfDirectory(atPath: srcRoot.path) else { return }
        for v in variants where !v.hasPrefix(".") {
            let src = srcRoot.appendingPathComponent(v, isDirectory: true)
            let dst = destRoot.appendingPathComponent(v, isDirectory: true)
            guard !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.moveItem(at: src, to: dst)
                Log.transcribe.info("adopted existing model download \(v, privacy: .public)")
            } catch {
                Log.transcribe.error("could not adopt \(v, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        // Remove the library's tree only if we emptied it.
        if let left = try? fm.contentsOfDirectory(atPath: srcRoot.path),
           left.filter({ !$0.hasPrefix(".") }).isEmpty {
            try? fm.removeItem(at: legacy)
        }
    }
}
