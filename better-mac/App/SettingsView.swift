import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted()

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
        .frame(minWidth: 420, minHeight: 360)
        .onAppear {
            accessibilityTrusted = Permissions.isAccessibilityTrusted()
        }
    }
}
