import SwiftUI
import Sparkle

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted()
    @State private var automaticallyChecksForUpdates: Bool = UpdaterController.shared.updater.automaticallyChecksForUpdates

    var body: some View {
        Form {
            Section("Features") {
                Toggle("Dynamic Island", isOn: $state.islandEnabled)
                Toggle("Volume HUD", isOn: $state.volumeHUDEnabled)
            }
            Section("Volume HUD") {
                Toggle("Show percentage", isOn: $state.showVolumePercentage)
            }
            Section("General") {
                Toggle("Open at Login", isOn: $state.openAtLogin)
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        UpdaterController.shared.updater.automaticallyChecksForUpdates = newValue
                    }
                HStack {
                    Text(appVersionString)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now…") {
                        UpdaterController.shared.checkForUpdates(nil)
                    }
                }
            }
            Section("Permissions") {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted ? "Accessibility: granted" : "Accessibility: required for Volume HUD")
                    Spacer()
                    Button("Open System Settings…") {
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 440)
        .onAppear {
            accessibilityTrusted = Permissions.isAccessibilityTrusted()
            automaticallyChecksForUpdates = UpdaterController.shared.updater.automaticallyChecksForUpdates
        }
    }

    private var appVersionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "better-mac \(short) (\(build))"
    }
}
