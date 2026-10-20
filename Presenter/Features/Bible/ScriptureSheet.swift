import SwiftUI
import UniformTypeIdentifiers
import PresenterCore

/// Type a reference ("Juan 3:16-18") or search for words, check the slides, and add the passage to the show.
/// Translations are public-domain or openly licensed files (Zefania, OSIS, USFX, USX) the operator imports; none are
/// bundled.
struct ScriptureSheet: View {
    let coordinator: PresentationCoordinator
    /// Called with the new show item, so the workspace can scroll to it.
    let onAdded: (PresentationItem) -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scriptureTranslationID") private var translationID = ""
    @AppStorage("scriptureVersesPerSlide") private var versesPerSlide = 2
    @AppStorage("scriptureShowsVerseNumbers") private var showsVerseNumbers = true
    @AppStorage("scriptureShowsReference") private var showsReference = true
    @State private var reference = ""
    @State private var search = ""
    @State private var themeID: UUID?
    @State private var importError: String?
    @State private var translationPendingRemoval: BibleStore.Entry?
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var draftAbbreviation = ""

    private var translation: BibleTranslation? {
        library.open.flatMap { $0.id.uuidString == translationID ? $0 : nil }
    }

    private var options: ScriptureSlides.Options {
        ScriptureSlides.Options(versesPerSlide: versesPerSlide, showsVerseNumbers: showsVerseNumbers, showsReference: showsReference)
    }

    /// The passage for the typed reference, or what's wrong with it.
    private var lookup: Result<BiblePassage, LookupError>? {
        let typed = reference.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, let translation else { return nil }
        do {
            return .success(try translation.passage(for: ScriptureReference.parse(typed)))
        } catch let error as ScriptureReference.ParseError {
            return .failure(LookupError(message: error.message(in: .english)))
        } catch let error as BiblePassageError {
            return .failure(LookupError(message: error.message(in: .english)))
        } catch {
            return .failure(LookupError(message: error.localizedDescription))
        }
    }

    private struct LookupError: Error {
        let message: String
    }

    private var passage: BiblePassage? {
        if case .success(let passage)? = lookup { passage } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Scripture").font(.title2.bold())
            translationRow
            if library.entries.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        referenceField
                        searchField
                    }
                    .frame(minWidth: 340)
                    preview
                        .frame(width: 240)
                }
                .frame(minHeight: 300)
                optionsRow
            }
            buttons
        }
        .padding(Spacing.xl)
        .frame(width: 680)
        .onAppear {
            themeID = coordinator.suggestedScriptureThemeID
            if library.entries.first(where: { $0.id.uuidString == translationID }) == nil {
                translationID = library.entries.first?.id.uuidString ?? ""
            }
        }
        .task(id: translationID) {
            if let id = UUID(uuidString: translationID) { await library.open(id) }
        }
        .confirmDeletion(
            "Remove this Bible?",
            message: "Slides already made from it stay as they are. You can import the file again later.",
            of: $translationPendingRemoval
        ) { entry in
            library.delete(entry.id)
            translationID = library.entries.first?.id.uuidString ?? ""
        }
    }

    // MARK: Translation

    private var translationRow: some View {
        HStack {
            if !library.entries.isEmpty {
                Picker("Bible", selection: $translationID) {
                    ForEach(library.entries) { entry in
                        Text("\(entry.name) (\(entry.abbreviation))").tag(entry.id.uuidString)
                    }
                }
                .fixedSize()
            }
            Button("Import Bible…") { importBible() }
                .disabled(library.isWorking)
            if let entry = library.entries.first(where: { $0.id.uuidString == translationID }) {
                Button("Rename…") {
                    draftName = entry.name
                    draftAbbreviation = entry.abbreviation
                    isRenaming = true
                }
                .disabled(translation == nil)
                .help("Change the name and the abbreviation that slides show, like “KJV”")
                .popover(isPresented: $isRenaming) {
                    PopoverForm("Rename Bible", primary: "Rename", width: 280, onCancel: { isRenaming = false }) {
                        rename()
                        isRenaming = false
                    } fields: {
                        TextField("Name", text: $draftName).textFieldStyle(.roundedBorder)
                        TextField("Abbreviation, shown on slides", text: $draftAbbreviation).textFieldStyle(.roundedBorder)
                    }
                }
                Button("Remove…") { translationPendingRemoval = entry }
                    .help("Remove \(entry.name) from Presenter")
            }
            if library.isWorking { ProgressView().controlSize(.small) }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let importError { WarningLabel(importError) }
            Text("Import a Bible to start. Presenter reads Zefania, OSIS, USFX and USX files, the free formats public-domain and open translations are shared in, such as the King James Version, the World English Bible or the Reina-Valera 1909. For USX, choose the Bible's folder or all its book files. The README says where to find them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    /// Saves a new name and abbreviation for the open translation. Empty fields keep what it had.
    private func rename() {
        guard var updated = translation else { return }
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let abbreviation = draftAbbreviation.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { updated.name = name }
        if !abbreviation.isEmpty { updated.abbreviation = abbreviation }
        library.update(updated)
    }

    private func importBible() {
        let types = [UTType.xml] + ["usx", "usfx"].compactMap { UTType(filenameExtension: $0) }
        let urls = MediaPanel.choose(types, multiple: true, folders: true,
                                     message: "Choose a Bible file (Zefania, OSIS, USFX), or a USX Bible's folder or book files.")
        guard !urls.isEmpty else { return }
        importError = nil
        Task {
            do {
                translationID = try await library.importFiles(at: urls).uuidString
            } catch let failure as BibleLibrary.ImportFailure {
                importError = failure.message
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    // MARK: Reference and search

    private var referenceField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Reference, like Juan 3:16-18 or 1 Co 13:4-7", text: $reference)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            Group {
                switch lookup {
                case .success(let passage)?:
                    Label("\(passage.caption) · \(passage.verses.count == 1 ? "1 verse" : "\(passage.verses.count) verses")",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                case .failure(let error)?:
                    WarningLabel(error.message)
                case nil:
                    Text(translation == nil ? "Opening the Bible…" : "Book names and abbreviations work in English and Spanish.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            if let importError { WarningLabel(importError).font(.caption) }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Or search for words", text: $search)
                .textFieldStyle(.roundedBorder)
            if let translation, !search.trimmingCharacters(in: .whitespaces).isEmpty {
                let hits = BibleSearch.search(search, in: translation)
                if hits.isEmpty {
                    Text("No verses have all those words.").font(.caption).foregroundStyle(.secondary)
                } else {
                    List(hits, id: \.self) { hit in
                        Button {
                            reference = hit.reference(in: translation.language)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.reference(in: translation.language)).font(.caption.bold())
                                Text(hit.text).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 160)
                    Text(hits.count == 200 ? "The first 200 verses. Add words to narrow it down." : "Click a verse to use it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Preview and options

    /// The slides the passage will make, so the split can be checked before adding.
    private var preview: some View {
        let slides = passage.map { ScriptureSlides.make($0, options: options) } ?? []
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(slides.count == 1 ? "1 slide" : "\(slides.count) slides")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                                if let label = slide.label { Text(label).foregroundStyle(.secondary) }
                            }
                            .font(.caption2)
                            Text(slide.primaryText)
                                .font(.caption)
                                .lineLimit(5)
                        }
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card))
                    }
                }
            }
        }
    }

    private var optionsRow: some View {
        HStack(spacing: Spacing.lg) {
            Picker("Verses per slide", selection: $versesPerSlide) {
                ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
            }
            .fixedSize()
            Toggle("Verse numbers", isOn: $showsVerseNumbers)
            Toggle("Reference", isOn: $showsReference)
                .help("Show the reference and translation on each slide")
            Picker("Theme", selection: $themeID) {
                Text("None").tag(UUID?.none)
                Divider()
                ForEach(coordinator.project.themes) { theme in
                    Text(theme.name.isEmpty ? "Untitled Theme" : theme.name).tag(Optional(theme.id))
                }
            }
            .fixedSize()
        }
    }

    private var buttons: some View {
        HStack {
            Text("Public-domain translations only. Presenter doesn't download or include any.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add to Show") {
                if let passage, let item = coordinator.addScripture(passage, options: options, themeID: themeID) {
                    onAdded(item)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(passage == nil)
        }
    }
}
