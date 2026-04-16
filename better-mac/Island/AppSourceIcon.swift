import SwiftUI
import AppKit

struct AppSourceIcon: View {
    let bundleID: String?

    var body: some View {
        if let image = Self.icon(forBundleID: bundleID) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "music.note")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
