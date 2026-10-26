import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

/// Imports song files (ProPresenter, OpenLyrics, ChordPro, SongSelect, plain lyrics) into the library and the open show. Files are
/// read when chosen, so the list shows each song's title, writers and slides, or why a file couldn't be read, before
/// anything is added.
struct ImportSongsSheet: View {
    let coordinator: PresentationCoordinator
    /// Called with the first new show item, so the workspace can scroll to it.
    let onImported: (PresentationItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files: [ImportedFile] = []
    @State private var isReading = false
    @State private var hasAskedForFiles = false
    /// 0 keeps whole sections on one slide.
    @State private var maxLines = 0
    /// Starts as the project's default theme.
    @State private var themeID: UUID?

    /// Debug builds: a folder whose files the sheet reads at launch instead of asking with the open panel, which
    /// synthetic clicks and keystrokes can't drive. Also opens the sheet (see `OperatorView`).
    static let debugFolderKey = "PresenterDebugImportSongs"

    private struct ImportedFile: Identifiable {
        let id = UUID()
        let fileName: String
        let result: Result<ImportedSong, SongImporter.ImportError>
        var isIncluded = true

        var song: ImportedSong? { try? result.get() }
    }

    private var chosenSongs: [ImportedSong] {
        files.filter(\.isIncluded).compactMap(\.song)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Import Songs").font(.title2.bold())

            list
                .frame(minHeight: 240)

            Text("Reads ProPresenter 7 (.pro), OpenLyrics (.xml), ChordPro (.cho, .chordpro, .pro), SongSelect lyrics (.txt) and SongPro (.usr) files, and plain lyrics in text files. Chords are left out. Writers, copyright and CCLI numbers are kept with each song.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Picker("Lines per slide", selection: $maxLines) {
                    Text("Whole section").tag(0)
                    Text("2 lines").tag(2)
                    Text("3 lines").tag(3)
                    Text("4 lines").tag(4)
                }
                .fixedSize()
                Picker("Theme", selection: $themeID) {
                    Text("None").tag(UUID?.none)
                    Divider()
                    ForEach(coordinator.project.themes) { theme in
                        Text(theme.name.isEmpty ? "Untitled Theme" : theme.name).tag(Optional(theme.id))
                    }
                }
                .fixedSize()
                Spacer()
                Button("Add Files…") { chooseFiles() }
                    .disabled(isReading)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosenSongs.count == 1 ? "Import 1 Song" : "Import \(chosenSongs.count) Songs") {
                    let items = coordinator.importSongs(chosenSongs, maxLinesPerSlide: maxLines == 0 ? nil : maxLines,
                                                        themeID: themeID)
                    if let first = items.first { onImported(first) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosenSongs.isEmpty || isReading)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 640)
        .onAppear {
            themeID = coordinator.defaultThemeID
            // Straight to the files, the first time: that's what the menu item asked for.
            guard !hasAskedForFiles else { return }
            hasAskedForFiles = true
            #if DEBUG
            if let folder = UserDefaults.standard.string(forKey: Self.debugFolderKey), !folder.isEmpty {
                let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                                          includingPropertiesForKeys: nil)) ?? []
                read(urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
                return
            }
            #endif
            DispatchQueue.main.async {
                chooseFiles()
                if files.isEmpty && !isReading { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if files.isEmpty {
            VStack(spacing: Spacing.sm) {
                if isReading {
                    ProgressView().controlSize(.small)
                    Text("Reading…").foregroundStyle(.secondary)
                } else {
                    Text("No songs chosen").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card))
        } else {
            List($files) { $file in
                row($file)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    private func row(_ file: Binding<ImportedFile>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            switch file.wrappedValue.result {
            case .success(let song):
                Toggle(song.title, isOn: file.isIncluded)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(song.title).font(.headline)
                    Text(detail(song)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(file.wrappedValue.fileName).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            case .failure(let error):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(file.wrappedValue.fileName).font(.headline)
                    Text(message(error)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func detail(_ song: ImportedSong) -> String {
        var parts = [song.slideCount == 1 ? "1 slide" : "\(song.slideCount) slides"]
        if !song.info.authors.isEmpty { parts.append(song.info.authorLine) }
        if !song.info.ccliNumber.isEmpty { parts.append("CCLI \(song.info.ccliNumber)") }
        if song.arrangement != nil { parts.append("with its song order") }
        return parts.joined(separator: " · ")
    }

    private func message(_ error: SongImporter.ImportError) -> String {
        switch error {
        case .unreadable: "Not a song file Presenter can read."
        case .malformed: "The file is damaged or incomplete."
        case .noLyrics: "No words found."
        }
    }

    private func chooseFiles() {
        let types = SongImporter.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        let urls = MediaPanel.choose(types, multiple: true, message: "Choose song files to import.")
        read(urls)
    }

    private func read(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isReading = true
        Task {
            // Off the main thread: a folder's worth of songs takes a moment to read.
            let read = await Task.detached {
                urls.map { url in
                    let result: Result<ImportedSong, SongImporter.ImportError>
                    if let data = try? Data(contentsOf: url) {
                        result = Result { () throws(SongImporter.ImportError) in
                            try SongImporter.parse(data, fileName: url.lastPathComponent)
                        }
                    } else {
                        result = .failure(.unreadable)
                    }
                    return ImportedFile(fileName: url.lastPathComponent, result: result)
                }
            }.value
            files.append(contentsOf: read)
            isReading = false
        }
    }
}
