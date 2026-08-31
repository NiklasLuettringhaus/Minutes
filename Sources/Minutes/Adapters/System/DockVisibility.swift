import AppKit

/// The Dock icon, switchable at runtime.
///
/// `LSUIElement` in Info.plist decides the *launch* policy, and FR-1 wants a menu
/// bar tool, so it stays true and this overrides it afterwards when asked. Two
/// details are not optional:
///
///  - Going `.regular` steals key window status from whatever the app had open, so
///    focus is restored explicitly afterwards. Without it the Settings window ends
///    up visible but dead to the keyboard.
///  - Going `.accessory` while a window is frontmost leaves macOS with no app to
///    focus, so the frontmost application is re-activated by hand.
@MainActor
enum DockVisibility {
    static func apply(_ show: Bool) {
        let app = NSApplication.shared
        let wanted: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard app.activationPolicy() != wanted else { return }

        let keyWindow = app.keyWindow
        app.setActivationPolicy(wanted)

        if show {
            app.activate(ignoringOtherApps: true)
            keyWindow?.makeKeyAndOrderFront(nil)
        } else if keyWindow != nil {
            // The window stays; it just no longer belongs to a Dock-visible app.
            app.activate(ignoringOtherApps: true)
            keyWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
