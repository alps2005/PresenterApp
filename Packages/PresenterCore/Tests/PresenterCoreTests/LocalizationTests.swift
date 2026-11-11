import Foundation
import XCTest
@testable import PresenterCore

final class LocalizationTests: XCTestCase {
    func testPreferredLanguage() {
        XCTAssertEqual(AppLanguage.preferred(from: ["es-MX", "en-US"]), .spanish)
        XCTAssertEqual(AppLanguage.preferred(from: ["es_419"]), .spanish)
        XCTAssertEqual(AppLanguage.preferred(from: ["fr-FR", "en-GB"]), .english, "The first language the apps know")
        XCTAssertEqual(AppLanguage.preferred(from: ["pt-BR"]), .english, "English when none is known")
        XCTAssertEqual(AppLanguage.preferred(from: []), .english)
    }

    func testTextIsTranslatedAndFilled() {
        XCTAssertEqual(Localization.text("Nothing is live.", in: .spanish), "No hay nada en vivo.")
        XCTAssertEqual(Localization.text("Nothing is live.", in: .english), "Nothing is live.")
        XCTAssertEqual(Localization.text("“{0}” is missing, used in “{1}”.", arguments: ["a.jpg", "Bienvenida"], in: .spanish),
                       "Falta “a.jpg”, que se usa en “Bienvenida”.")
        XCTAssertEqual(Localization.text("Not in any table {0}", arguments: ["x"], in: .spanish), "Not in any table x",
                       "A missing translation shows the English")
    }

    func testPlaceholders() {
        XCTAssertEqual(Localization.placeholders(in: "{0} and {1}, not {x} or {}"), ["{0}", "{1}"])
    }

    /// Every word the engine and the bridge send through `Localization.text`, or name an undo step with, has a Spanish
    /// translation that keeps its placeholders.
    func testEveryEngineTextHasASpanishTranslation() throws {
        // The engine, and the Windows bridge beside it, which sends its own messages through the same table.
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = [package.appendingPathComponent("Sources/PresenterCore"),
                       package.deletingLastPathComponent().appendingPathComponent("PresenterBridge/Sources/PresenterBridge")]
        let files = try folders.flatMap { folder in
            try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        XCTAssertTrue(files.contains { $0.lastPathComponent == "BridgeSession.swift" }, "The bridge is scanned too")
        XCTAssertFalse(files.isEmpty)

        // The first argument when it's a literal, or both sides of a `condition ? "A" : "B"` choice.
        let string = #""((?:[^"\\]|\\.)*)""#
        let call = try NSRegularExpression(
            pattern: #"(?:Localization\.text|recordingUndo)\(\s*(?:[^"\n]*?\?\s*)?"# + string + #"(?:\s*:\s*"# + string + ")?")
        var keys: Set<String> = []
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8) as NSString
            for match in call.matches(in: code as String, range: NSRange(location: 0, length: code.length)) {
                for group in 1...2 where match.range(at: group).location != NSNotFound {
                    keys.insert(code.substring(with: match.range(at: group)))
                }
            }
        }
        XCTAssertGreaterThan(keys.count, 100, "The scan found the engine's words")

        let spanish = Localization.table(for: .spanish)
        for key in keys.sorted() {
            guard let translation = spanish[key] else {
                XCTFail("No Spanish for “\(key)”")
                continue
            }
            XCTAssertEqual(Localization.placeholders(in: translation), Localization.placeholders(in: key),
                           "“\(translation)” keeps the placeholders of “\(key)”")
        }
    }

    @MainActor
    func testUndoNamesFollowTheLanguage() {
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T"))
        _ = coordinator.addSong(title: "A", lyrics: "Verse 1\nA")
        XCTAssertEqual(coordinator.undoActionName, "Add Song")
        Localization.language = .spanish
        defer { Localization.language = .english }
        XCTAssertEqual(coordinator.undoActionName, "Agregar canción")
        XCTAssertEqual(CommandRejection.nothingLive.message, "No hay nada en vivo.")
    }
}
