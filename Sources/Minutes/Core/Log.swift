import Foundation
import os

/// One category per layer (architecture convention).
///
/// Every CoreAudio `OSStatus` is logged at the boundary — the spikes proved that a
/// silent failure in that stack is only ever found by instrumenting each call.
/// Transcript text is never logged.
enum Log {
    private static let subsystem = "dev.niklas.minutes"
    static let app        = Logger(subsystem: subsystem, category: "app")
    static let session    = Logger(subsystem: subsystem, category: "session")
    static let audio      = Logger(subsystem: subsystem, category: "audio")
    static let pipeline   = Logger(subsystem: subsystem, category: "pipeline")
    static let detection  = Logger(subsystem: subsystem, category: "detection")
    static let transcribe = Logger(subsystem: subsystem, category: "transcribe")
    static let store      = Logger(subsystem: subsystem, category: "store")
    static let ui         = Logger(subsystem: subsystem, category: "ui")
}
