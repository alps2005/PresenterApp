import Foundation
import PresenterCore

/// One open project for the Windows app: the coordinator, where the project lives, and saving. The app sends
/// commands as JSON (see `BridgeCommand`) and reads the state back as JSON (see `BridgeState`).
///
/// The project is saved after every command that changes it, so nothing is lost if the app is closed or crashes.
@MainActor
public final class BridgeSession {
    public let coordinator: PresentationCoordinator
    public let dataDirectory: URL
    let store: ProjectStore
    let backups: ProjectBackups
    let mediaDirectory: URL
    /// What went wrong loading or saving, for the operator to read. Cleared when they dismiss it.
    public private(set) var problem: String?
    /// Goes up each time the project changes, so the app redraws its lists only when there's something new.
    public private(set) var projectRevision = 0
    private var lastSaved: ProjectDocument

    /// Opens the project in `dataDirectory` (`Project.json`, `Media/`, `Backups/`), as the Mac app keeps it in
    /// Application Support. Nothing there yet starts a new, empty project, written once something changes.
    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
        store = ProjectStore(fileURL: dataDirectory.appendingPathComponent("Project.json"))
        backups = ProjectBackups(projectFileURL: store.fileURL)
        mediaDirectory = dataDirectory.appendingPathComponent("Media", isDirectory: true)
        let outcome = ProjectLoader.loadInitialProject(from: store, backups: backups)
        coordinator = PresentationCoordinator(project: outcome.project)
        problem = outcome.problem
        // A new project isn't written until the operator changes it; a loaded one already matches the file. (Opening
        // marks the show as opened, which isn't worth a save by itself.)
        lastSaved = coordinator.project
    }

    // MARK: - Commands

    /// Runs one command, given as JSON, and answers as JSON: `{"ok": true}` plus anything the command returns, or
    /// `{"ok": false, "error": "…"}` with a sentence for the operator.
    public func send(_ json: String) -> String {
        let reply: BridgeReply
        do {
            let command = try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
            reply = try run(command)
        } catch let error as BridgeError {
            reply = .failure(error.message)
        } catch is DecodingError {
            reply = .failure(Localization.text("The app sent a command the engine doesn't understand."))
        } catch {
            reply = .failure(error.localizedDescription)
        }
        saveIfChanged()
        return BridgeJSON.encode(reply)
    }

    /// Moves the live slide on when its countdown is over. Returns true when the app should read the state again:
    /// the slide moved, or the live slide shows the time or a timer.
    public func tick() -> Bool {
        let moved = coordinator.advanceIfDue()
        guard !moved, case .slide(let rendered) = coordinator.audienceScene else { return moved }
        return rendered.slide.elements.contains { element in
            if case .text(let text) = element { LiveText.hasTokens(text.text) } else { false }
        }
    }

    /// Writes the project if it changed since the last save. The app also calls it before closing.
    public func saveIfChanged() {
        let project = coordinator.project
        guard project != lastSaved else { return }
        projectRevision += 1
        do {
            try store.save(project)
            lastSaved = project
        } catch {
            problem = (error as? ProjectStoreError)?.message ?? error.localizedDescription
        }
    }

    private func run(_ command: BridgeCommand) throws -> BridgeReply {
        let coordinator = coordinator
        switch command.type {
        // Live
        case "selectItem": return try result(coordinator.selectItem(command.require(\.itemID)))
        case "cue":
            return try result(coordinator.cueSlide(command.require(\.slideID), inItem: command.require(\.itemID),
                                                   occurrence: command.occurrence ?? 0))
        case "takeLive":
            return try result(coordinator.takeLive(slideID: command.require(\.slideID), inItem: command.require(\.itemID),
                                                   occurrence: command.occurrence ?? 0))
        case "takeLiveCued": return result(coordinator.takeLive())
        case "next": return result(coordinator.nextSlide())
        case "previous": return result(coordinator.previousSlide())
        case "clearSlide": return result(coordinator.clearOutput())
        case "clearBackground": return result(coordinator.clearBackground())
        case "clearAll": return result(coordinator.clearAll())
        case "blackout": return result(coordinator.blackout())
        case "restore": return result(coordinator.restoreOutput())
        case "section":
            guard let key = try command.require(\.key).first, let kind = SongSectionKind(hotkey: key) else {
                throw BridgeError(Localization.text("That key doesn't name a section."))
            }
            return result(coordinator.takeLiveSection(kind, number: command.number))

        // Songs and the library
        case "addSong":
            guard let item = coordinator.addSong(title: command.title ?? "", lyrics: try command.require(\.text)) else {
                throw BridgeError(Localization.text("Type or paste the song's words first."))
            }
            return .success(["itemID": item.id.uuidString])
        case "importSongs": return try importSongs(at: command.require(\.paths))
        case "words":
            let presentationID = try command.require(\.presentationID)
            guard let presentation = coordinator.project.presentation(withID: presentationID) else {
                throw BridgeError(CommandRejection.unknownPresentation.message)
            }
            return .success(["title": presentation.title, "text": presentation.reflowText])
        case "editWords":
            let presentationID = try command.require(\.presentationID)
            let text = try command.require(\.text)
            guard !LyricsParser.slides(from: text).isEmpty else {
                throw BridgeError(Localization.text("A presentation needs at least one slide. Type some words first."))
            }
            if let title = command.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                _ = coordinator.renamePresentation(presentationID, to: title)
            }
            return result(coordinator.reflow(text, presentationID: presentationID))
        case "renamePresentation":
            return try result(coordinator.renamePresentation(command.require(\.presentationID), to: command.require(\.title)))
        case "deletePresentation": return try result(coordinator.deletePresentation(command.require(\.presentationID)))
        case "addToShow":
            guard coordinator.addToPlaylist(try command.require(\.presentationID)) != nil else {
                throw BridgeError(CommandRejection.unknownPresentation.message)
            }
            return .success()
        case "removeItem": return try result(coordinator.removeItem(command.require(\.itemID)))
        case "moveItem":
            let itemID = try command.require(\.itemID)
            let destination = try command.require(\.index)
            guard let index = coordinator.project.playlist.index(ofItem: itemID) else {
                throw BridgeError(CommandRejection.unknownItem.message)
            }
            // `destination` is where the item ends up; moveItems counts positions before the move.
            let offset = destination > index ? destination + 1 : destination
            return result(coordinator.moveItems(fromOffsets: IndexSet(integer: index), toOffset: offset))

        // Shows
        case "openShow": return try result(coordinator.openPlaylist(command.require(\.showID)))
        case "addShow":
            let show = coordinator.addPlaylist(title: command.title ?? "")
            return .success(["showID": show.id.uuidString])
        case "renameShow": return try result(coordinator.renamePlaylist(command.require(\.showID), to: command.require(\.title)))
        case "deleteShow": return try result(coordinator.deletePlaylist(command.require(\.showID)))

        // The project
        case "undo":
            guard coordinator.canUndo else { throw BridgeError(Localization.text("There's nothing to undo.")) }
            coordinator.undo()
            return .success()
        case "redo":
            guard coordinator.canRedo else { throw BridgeError(Localization.text("There's nothing to redo.")) }
            coordinator.redo()
            return .success()
        case "openProject": return try openProject(at: command.require(\.path))
        case "exportProject": return try exportProject(to: command.require(\.path))
        case "dismissProblem":
            problem = nil
            return .success()
        default:
            throw BridgeError(Localization.text("The app sent a command the engine doesn't know: {0}.", command.type))
        }
    }

    private func result(_ result: CommandResult) -> BridgeReply {
        switch result {
        case .applied: .success()
        case .rejected(let rejection): .failure(rejection.message)
        }
    }

    // MARK: - Files

    /// Reads song files and adds the ones that read to the library and the open show, as one change to undo.
    /// The reply lists the files that didn't, with why.
    private func importSongs(at paths: [String]) throws -> BridgeReply {
        var songs: [ImportedSong] = []
        var failures: [[String: String]] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let reason: String
            do {
                let data = try Data(contentsOf: url)
                songs.append(try SongImporter.parse(data, fileName: url.lastPathComponent))
                continue
            } catch let error as SongImporter.ImportError {
                reason = switch error {
                case .unreadable: Localization.text("Not a song file Presenter can read.")
                case .malformed: Localization.text("The file is damaged or incomplete.")
                case .noLyrics: Localization.text("No words found.")
                }
            } catch {
                reason = Localization.text("The file couldn't be read.")
            }
            failures.append(["file": url.lastPathComponent, "reason": reason])
        }
        let added = coordinator.importSongs(songs)
        return BridgeReply(ok: true, values: ["added": .int(added.count), "failures": .list(failures)])
    }

    /// Replaces the project with a file the operator picked: one exported from Presenter on a Mac or PC (with its
    /// pictures and videos), or a plain `Project.json`. The current project is backed up first; the reply says where.
    private func openProject(at path: String) throws -> BridgeReply {
        let url = URL(fileURLWithPath: path)
        let opened: ProjectDocument
        do {
            opened = try ProjectArchive.open(Data(contentsOf: url), mediaDirectory: mediaDirectory)
        } catch let error as ProjectStoreError {
            throw BridgeError(error.message)
        } catch {
            throw BridgeError(Localization.text("The file couldn't be read. {0}", error.localizedDescription))
        }
        saveIfChanged()
        let backup: URL
        do {
            backup = try backups.save(coordinator.project)
        } catch {
            throw BridgeError(Localization.text("The current project couldn't be backed up, so it wasn't replaced. {0}", error.localizedDescription))
        }
        coordinator.replaceProject(opened)
        return .success(["backup": BridgeJSON.path(backup)])
    }

    /// Writes the project with its pictures and videos as one file, to open on another computer.
    private func exportProject(to path: String) throws -> BridgeReply {
        do {
            let data = try ProjectArchive.export(coordinator.project, mediaDirectory: mediaDirectory)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch let error as ProjectStoreError {
            throw BridgeError(error.message)
        } catch {
            throw BridgeError(Localization.text("The project couldn't be exported. {0}", error.localizedDescription))
        }
        return .success()
    }

    // MARK: - State

    /// Everything the app draws, as JSON: see `BridgeState`.
    public func stateJSON(now: Date = Date()) -> String {
        BridgeJSON.encode(BridgeState(session: self, now: now))
    }

    /// Where an imported picture or video is on disk, in the platform's own form (`C:\…` on Windows).
    func mediaPath(_ assetID: UUID) -> String? {
        guard let asset = coordinator.project.asset(withID: assetID) else { return nil }
        return BridgeJSON.path(mediaDirectory.appendingPathComponent(asset.storedFilename))
    }
}

/// A command from the app. Every command has a `type`; the other fields are the ones that command needs.
struct BridgeCommand: Decodable {
    var type: String
    var itemID: UUID?
    var slideID: UUID?
    var occurrence: Int?
    var presentationID: UUID?
    var showID: UUID?
    var title: String?
    var text: String?
    var key: String?
    var number: Int?
    var index: Int?
    var path: String?
    var paths: [String]?

    func require<Value>(_ field: KeyPath<BridgeCommand, Value?>) throws -> Value {
        guard let value = self[keyPath: field] else {
            throw BridgeError(Localization.text("The app left out part of a {0} command.", type))
        }
        return value
    }
}

struct BridgeError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
