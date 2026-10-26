import AppKit
import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

extension SongUsageLog {
    /// The log beside the project, in the app's data folder.
    static var app: SongUsageLog {
        SongUsageLog(fileURL: AppDirectories.data.appendingPathComponent("SongUsage.jsonl"))
    }
}

/// The church's CCLI licence, whether songs show their credits, and which songs were shown between two dates, with
/// a CSV export for CCLI reporting.
struct CCLIReportSheet: View {
    let coordinator: PresentationCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var licenseDraft = ""
    /// CCLI reporting periods are six months long.
    @State private var start = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
    @State private var end = Date.now
    @State private var entries: [SongUsageLog.Entry] = []
    @State private var problem: String?

    private var rows: [SongUsageLog.Row] {
        SongUsageLog.report(entries, from: start, to: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("CCLI Report").font(.title2.bold())

            Form {
                TextField("Church CCLI License #", text: $licenseDraft, prompt: Text("e.g. 1234567"))
                    .onSubmit { saveLicense() }
                Toggle("Show song credits on each song's first and last slide", isOn: Binding(
                    get: { coordinator.project.ccli.showsCredits },
                    set: { coordinator.setCCLISettings(CCLISettings(licenseNumber: licenseDraft, showsCredits: $0)) }
                ))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 110)

            HStack {
                DatePicker("Songs shown from", selection: $start, displayedComponents: .date)
                DatePicker("to", selection: $end, in: start..., displayedComponents: .date)
                Spacer()
            }
            .fixedSize(horizontal: false, vertical: true)

            Table(rows) {
                TableColumn("Song", value: \.title)
                TableColumn("Writers", value: \.authors)
                TableColumn("CCLI #", value: \.ccliNumber).width(90)
                TableColumn("Times") { Text("\($0.uses)").monospacedDigit() }.width(50)
                TableColumn("Last Used") { Text($0.lastUsed, format: .dateTime.day().month().year()) }.width(100)
            }
            .frame(minHeight: 240)
            .overlay {
                if rows.isEmpty {
                    Text("No songs were shown in these dates. A song counts once a day, when it goes live.")
                        .foregroundStyle(.secondary)
                }
            }

            if let problem { WarningLabel(problem) }

            HStack {
                Text("Songs count when they go live, on this Mac. Submit the counts at reporting.ccli.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export CSV…") { exportCSV() }
                    .disabled(rows.isEmpty)
                Button("Done") {
                    saveLicense()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 720)
        .onAppear { licenseDraft = coordinator.project.ccli.licenseNumber }
        .task {
            let log = SongUsageLog.app
            do {
                entries = try await Task.detached(priority: .userInitiated) { try log.entries() }.value
            } catch {
                problem = "The song usage log couldn't be read: \(error.localizedDescription)"
            }
        }
    }

    private func saveLicense() {
        coordinator.setCCLISettings(CCLISettings(licenseNumber: licenseDraft,
                                                 showsCredits: coordinator.project.ccli.showsCredits))
        licenseDraft = coordinator.project.ccli.licenseNumber
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "CCLI Report \(formatter.string(from: start)) to \(formatter.string(from: end)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SongUsageLog.csv(rows, dateFormatter: formatter).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            problem = "The report couldn't be saved: \(error.localizedDescription)"
        }
    }
}
