import Foundation
import Observation
import os
import PresenterCore

/// The imported Bible translations (see `BibleStore`, in `Application Support/Presenter/Bibles`), and the one open in
/// the Scripture sheet. Reading and parsing happen off the main actor; only one translation is kept in memory.
@Observable
final class BibleLibrary {
    private(set) var entries: [BibleStore.Entry]
    /// The translation the Scripture sheet last opened.
    private(set) var open: BibleTranslation?
    private(set) var isWorking = false

    @ObservationIgnored let store: BibleStore
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.alps2005.Presenter", category: "Bible")

    init() {
        store = BibleStore(directory: AppDirectories.data.appendingPathComponent("Bibles", isDirectory: true))
        entries = store.entries()
    }

    /// Imports a Bible: one Zefania, OSIS or USFX file, or a USX Bible's book files or folder. Returns the new
    /// translation's ID, or throws a message for the operator.
    func importFiles(at urls: [URL]) async throws -> UUID {
        isWorking = true
        defer { isWorking = false }
        let store = store
        do {
            let entry = try await Task.detached(priority: .userInitiated) { try store.importFiles(at: urls) }.value
            entries = store.entries()
            logger.info("Imported \(entry.abbreviation, privacy: .public): \(entry.verseCount) verses")
            return entry.id
        } catch let error as BibleFileParser.ParseError {
            throw ImportFailure(message: Self.message(for: error))
        } catch {
            throw ImportFailure(message: "Couldn't read that file: \(error.localizedDescription)")
        }
    }

    /// Opens a translation, reading it from disk unless it's already open.
    func open(_ id: UUID) async {
        if open?.id == id { return }
        isWorking = true
        defer { isWorking = false }
        let store = store
        do {
            open = try await Task.detached(priority: .userInitiated) { try store.load(id) }.value
        } catch {
            open = nil
            logger.error("Couldn't open Bible \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Saves a change to the open translation's name, abbreviation or language.
    func update(_ translation: BibleTranslation) {
        do {
            try store.save(translation)
            entries = store.entries()
            if open?.id == translation.id { open = translation }
        } catch {
            logger.error("Couldn't save Bible \(translation.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func delete(_ id: UUID) {
        try? store.delete(id)
        entries = store.entries()
        if open?.id == id { open = nil }
    }

    struct ImportFailure: Error {
        let message: String
    }

    private static func message(for error: BibleFileParser.ParseError) -> String {
        switch error {
        case .notABible: "That isn't a Bible Presenter can read: a Zefania, OSIS, USFX or USX file."
        case .malformed: "That Bible file is damaged or incomplete."
        case .noVerses: "That Bible file has no verses Presenter can read."
        }
    }
}
