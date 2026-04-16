import AppKit
import ApplicationServices

enum Permissions {
    /// Non-prompting check. Use this on launch to decide whether to show an
    /// onboarding alert. Equivalent to AXIsProcessTrusted() without the side
    /// effect of the system prompt.
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows a non-blocking NSAlert once per process that explains why the app
    /// needs Accessibility and offers a button to jump to System Settings.
    static func promptAccessibilityIfNeeded() {
        if isAccessibilityTrusted() { return }
        if promptedThisProcess { return }
        promptedThisProcess = true

        Log.perm.info("Prompting for Accessibility")

        let alert = NSAlert()
        alert.messageText = "NotchFree needs Accessibility access"
        alert.informativeText = """
        To intercept volume key presses and replace the native macOS volume indicator, NotchFree needs the Accessibility permission. It does not read regular keystrokes, clipboard data, or passwords.

        Toggle NotchFree ON under System Settings → Privacy & Security → Accessibility.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings…")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Internal gate so we don't prompt repeatedly in one session.
    private nonisolated(unsafe) static var promptedThisProcess = false
}
