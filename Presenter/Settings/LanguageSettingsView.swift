import AppKit
import os
import SwiftUI

/// Settings › Language: English or Spanish, or whichever of them macOS prefers. macOS reads an app's language when it
/// starts, so the choice applies the next time Presenter opens; Restart Now does that, but never mid-service.
struct LanguageSettingsView: View {
    /// Whether anything is on an output now, when restarting would take it off.
    let isPresenting: () -> Bool
    @State private var choice = LanguageChoice.current()
    /// What this run of Presenter started with, to know whether a restart is needed.
    @State private var launchedWith = LanguageChoice.current()

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $choice) {
                    ForEach(LanguageChoice.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .onChange(of: choice) { _, newChoice in newChoice.apply() }
                Text("Menus, windows and messages. Your songs and slides stay as you wrote them.")
                    .settingsNote()
            }

            if choice != launchedWith {
                Section {
                    Text("Presenter changes language the next time it opens.")
                    HStack {
                        if isPresenting() {
                            Text("Something is on the audience output. Restart after the service.")
                                .settingsNote()
                        }
                        Spacer()
                        Button("Restart Presenter Now") { Self.relaunch() }
                            .disabled(isPresenting())
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    /// Quits (saving the project as any quit does) and opens Presenter again once this copy has gone.
    private static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath]
        do {
            try task.run()
            NSApp.terminate(nil)
            // Still here: the quit was cancelled (a save failed and the operator chose to stay), so don't reopen later.
            task.terminate()
        } catch {
            Log.app.error("Couldn't restart: \(error.localizedDescription, privacy: .public)")
        }
    }
}
