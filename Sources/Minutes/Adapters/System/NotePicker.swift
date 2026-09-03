import AppKit
import UniformTypeIdentifiers

/// The two AppKit panels FR-79 needs, behind one small surface.
///
/// Here rather than in `SessionCoordinator` because a coordinator that opens an
/// `NSOpenPanel` cannot be reasoned about without a window server — and the
/// decisions around these calls (which Meeting a file claims, whether to warn)
/// are the part worth testing, so they stay in the coordinator and the panels
/// stay here.
enum NotePicker {

    /// A Markdown file, starting in the Notes Folder.
    ///
    /// The app is not sandboxed (`Scripts/Minutes.entitlements`, AD-16), so a file
    /// inside the folder the user has already granted needs no second bookmark.
    static func chooseMarkdownFile(startingIn folder: URL) -> URL? {
        let p = NSOpenPanel()
        p.directoryURL = folder
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.message = "Choose the Markdown file that is this meeting's note."
        p.prompt = "Use This Note"
        // `UTType.markdown` does not exist; the type is registered under
        // `net.daringfireball.markdown` and is reached through the extension.
        if let md = UTType(filenameExtension: "md") {
            p.allowedContentTypes = [md]
        }
        return p.runModal() == .OK ? p.url : nil
    }

    /// A confirmation the user must actively accept.
    ///
    /// Returns true only for the confirm button. The default button is Cancel, so
    /// Return does not commit a link the app has just warned about.
    static func confirm(title: String, message: String, confirm: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .warning
        a.addButton(withTitle: "Cancel")
        a.addButton(withTitle: confirm)
        return a.runModal() == .alertSecondButtonReturn
    }
}
