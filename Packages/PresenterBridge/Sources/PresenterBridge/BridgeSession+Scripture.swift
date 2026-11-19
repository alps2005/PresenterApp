import Foundation
import PresenterCore

// Scripture for the Windows app, as the Mac app's Scripture window does it: Bibles the operator imports (Zefania,
// OSIS, USFX, USX), a typed reference or a word search, and the passage added to the show as text slides.
extension BridgeSession {
    /// The Bibles, the themes a passage can use, and the theme to suggest (one named Scripture, else the default).
    func biblesList() -> BridgeReply {
        let bibles = bibles.entries().map { entry in
            ["id": entry.id.uuidString, "name": entry.name, "abbreviation": entry.abbreviation,
             "language": entry.language.rawValue, "verseCount": String(entry.verseCount)]
        }
        let themes = coordinator.project.themes.map { theme in
            ["id": theme.id.uuidString, "name": theme.name.isEmpty ? Localization.text("Untitled Theme") : theme.name]
        }
        var values: [String: BridgeReply.Value] = ["bibles": .list(bibles), "themes": .list(themes)]
        if let suggested = coordinator.suggestedScriptureThemeID { values["suggestedThemeID"] = .string(suggested.uuidString) }
        return BridgeReply(ok: true, values: values)
    }

    /// Reads a Bible file, or a USX Bible's folder or book files, as one new translation.
    func importBible(at paths: [String]) throws -> BridgeReply {
        let entry: BibleStore.Entry
        do {
            entry = try bibles.importFiles(at: paths.map { URL(fileURLWithPath: $0) })
        } catch let error as BibleFileParser.ParseError {
            let message = switch error {
            case .notABible: Localization.text("That isn't a Bible Presenter can read: a Zefania, OSIS, USFX or USX file.")
            case .malformed(let detail): Localization.text("That Bible file is damaged or incomplete. {0}", detail)
            case .noVerses: Localization.text("That Bible file has no verses Presenter can read.")
            }
            throw BridgeError(message)
        } catch {
            throw BridgeError(Localization.text("Couldn't read that file: {0}", error.localizedDescription))
        }
        return .success(["bibleID": entry.id.uuidString, "name": entry.name])
    }

    func renameBible(_ id: UUID, name: String, abbreviation: String?) throws -> BridgeReply {
        var translation = try openBible(id)
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw BridgeError(Localization.text("Type a name for the Bible.")) }
        translation.name = name
        if let abbreviation = abbreviation?.trimmingCharacters(in: .whitespaces), !abbreviation.isEmpty {
            translation.abbreviation = abbreviation
        }
        do {
            try bibles.save(translation)
        } catch {
            throw BridgeError(Localization.text("The Bible couldn't be saved. {0}", String(describing: error)))
        }
        openBibles[id] = translation
        return .success()
    }

    /// Slides already made from it stay as they are: they're ordinary text in the project.
    func removeBible(_ id: UUID) throws -> BridgeReply {
        do {
            try bibles.delete(id)
        } catch {
            throw BridgeError(Localization.text("The Bible couldn't be removed. {0}", String(describing: error)))
        }
        openBibles[id] = nil
        return .success()
    }

    /// The verses for a typed reference, and how many slides they make, for the preview. A reference that doesn't
    /// read, or isn't in that Bible, is turned down with why, in the Bible's language.
    func lookUpScripture(_ id: UUID, reference: String, second secondID: UUID?, options: ScriptureSlides.Options) throws -> BridgeReply {
        let (passage, second) = try passages(id, reference: reference, second: secondID)
        let verses = passage.verses.map { ["chapter": String($0.chapter), "number": String($0.number), "text": $0.text] }
        var values: [String: BridgeReply.Value] = [
            "caption": .string(passage.caption),
            "verses": .list(verses),
            "slideCount": .int(ScriptureSlides.make(passage, second: second, options: options).count),
        ]
        if let secondID, secondID != id, second == nil {
            values["secondMissing"] = .string(Localization.text("The second Bible doesn't have this passage, so only the first is shown."))
        }
        return BridgeReply(ok: true, values: values)
    }

    /// Verses with all the words typed, in Bible order (at most 200).
    func searchBible(_ id: UUID, for query: String) throws -> BridgeReply {
        let translation = try openBible(id)
        let hits = BibleSearch.search(query, in: translation).map { hit in
            ["reference": hit.reference(in: translation.language), "text": hit.text]
        }
        return BridgeReply(ok: true, values: ["hits": .list(hits)])
    }

    /// Adds the passage to the library and the end of the show, and selects it.
    func addScripture(_ id: UUID, reference: String, second secondID: UUID?, options: ScriptureSlides.Options,
                      themeID: UUID?) throws -> BridgeReply {
        let (passage, second) = try passages(id, reference: reference, second: secondID)
        guard let item = coordinator.addScripture(passage, second: second, options: options, themeID: themeID) else {
            throw BridgeError(Localization.text("That passage has no verses."))
        }
        return .success(["itemID": item.id.uuidString])
    }

    func scriptureOptions(_ command: BridgeCommand) -> ScriptureSlides.Options {
        ScriptureSlides.Options(versesPerSlide: min(4, max(1, command.versesPerSlide ?? 2)),
                                showsVerseNumbers: command.showsVerseNumbers ?? true,
                                showsReference: command.showsReference ?? true)
    }

    /// The passage in the first Bible, and in the second when there is one and it has the passage.
    private func passages(_ id: UUID, reference: String, second secondID: UUID?) throws -> (BiblePassage, BiblePassage?) {
        let translation = try openBible(id, keeping: secondID)
        let typed = reference.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { throw BridgeError(Localization.text("Type a reference, like Juan 3:16-18.")) }
        let passage: BiblePassage
        do {
            passage = try translation.passage(for: ScriptureReference.parse(typed))
        } catch let error as ScriptureReference.ParseError {
            throw BridgeError(error.message(in: translation.language))
        } catch let error as BiblePassageError {
            throw BridgeError(error.message(in: translation.language))
        }
        guard let secondID, secondID != id else { return (passage, nil) }
        let second = try? openBible(secondID, keeping: id).passage(for: passage.reference)
        return (passage, second)
    }

    /// A Bible from disk, or the copy already open. Others than this one and `other` are closed, to keep memory down.
    private func openBible(_ id: UUID, keeping other: UUID? = nil) throws -> BibleTranslation {
        openBibles = openBibles.filter { $0.key == id || $0.key == other }
        if let open = openBibles[id] { return open }
        do {
            let translation = try bibles.load(id)
            openBibles[id] = translation
            return translation
        } catch .notFound {
            throw BridgeError(Localization.text("That Bible isn't there anymore. Import it again."))
        } catch {
            throw BridgeError(Localization.text("That Bible couldn't be read. Import it again."))
        }
    }
}
