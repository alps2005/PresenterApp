import AppKit
import PresenterCore
import SwiftUI

/// When the pre-service check was asked for: at launch it only opens with problems, and doesn't count an audience
/// output that's still off.
enum PreServiceCheckMode: Identifiable {
    case launch
    case menu

    var id: Self { self }
}

/// The open show's pre-service checklist: missing media and fonts, the audience display, empty presentations and
/// songs without credits, each with a way to go to it.
struct PreServiceCheckSheet: View {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let mode: PreServiceCheckMode
    /// Goes to a show item in the workspace.
    let onShow: (UUID) -> Void

    @Environment(MediaLibrary.self) private var mediaLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var problems: [PreServiceProblem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pre-Service Check").font(.title2.bold())
            Text(problems.isEmpty
                 ? "Everything “\(coordinator.project.playlist.title)” uses is ready."
                 : "Things to look at in “\(coordinator.project.playlist.title)” before the service:")
                .foregroundStyle(.secondary)

            if problems.isEmpty {
                Label("No problems found", systemImage: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(PreServiceProblem.Kind.allCases, id: \.self) { kind in
                        let rows = problems.filter { $0.kind == kind }
                        if !rows.isEmpty {
                            Section(kind.title) {
                                ForEach(rows) { problem in row(problem) }
                            }
                        }
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 260)
            }

            HStack {
                if mode == .launch {
                    Text("Shown at launch because something needs attention. Live › Pre-Service Check… (⌥⌘K) runs it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Again") { problems = Self.problems(coordinator, outputManager, mediaLibrary, mode: .menu) }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 620)
        .onAppear { problems = Self.problems(coordinator, outputManager, mediaLibrary, mode: mode) }
    }

    private func row(_ problem: PreServiceProblem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            WarningLabel(problem.message, font: .body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let itemID = problem.itemID {
                Button("Show") {
                    onShow(itemID)
                    dismiss()
                }
                .controlSize(.small)
            }
        }
    }

    static func problems(_ coordinator: PresentationCoordinator, _ outputManager: OutputManager,
                         _ mediaLibrary: MediaLibrary, mode: PreServiceCheckMode) -> [PreServiceProblem] {
        let store = mediaLibrary.store
        return PreServiceCheck.problems(
            in: coordinator.project,
            mediaExists: { store.fileExists(for: $0) },
            installedFonts: Set(NSFontManager.shared.availableFontFamilies),
            audience: outputManager.status(.audience),
            includesOutputOff: mode == .menu
        )
    }
}
