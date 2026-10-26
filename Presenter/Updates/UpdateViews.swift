import Sparkle
import SwiftUI

/// Presenter › Check for Updates…, and "Update to 1.3…" when a check found one while Presenter was presenting.
struct UpdateCommands: Commands {
    let updater: UpdaterController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updater.isAvailable {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                if let version = updater.availableVersion {
                    Button("Update to Presenter \(version)…") { updater.checkForUpdates() }
                }
            }
        }
    }
}

/// The Settings window's General tab: updates. Sparkle keeps the setting; it's set only when the operator changes it.
struct UpdateSettingsView: View {
    let updater: UpdaterController
    @State private var checksAutomatically = false

    var body: some View {
        Form {
            if let sparkle = updater.updater {
                Toggle("Check for updates once a day", isOn: $checksAutomatically)
                    .onAppear { checksAutomatically = sparkle.automaticallyChecksForUpdates }
                    .onChange(of: checksAutomatically) { _, isOn in
                        if sparkle.automaticallyChecksForUpdates != isOn { sparkle.automaticallyChecksForUpdates = isOn }
                    }
                Text("Presenter asks before installing, and never while a service is under way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } else {
                Text("This copy of Presenter doesn't update itself (a development build).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
