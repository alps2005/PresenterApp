import Foundation
import XCTest
@testable import PresenterCore

/// Fixtures use public-domain hymns; the CCLI numbers and licence lines are made up.
final class SongImportTests: XCTestCase {
    private func parse(_ text: String, _ fileName: String) throws -> ImportedSong {
        try SongImporter.parse(Data(text.utf8), fileName: fileName)
    }

    // MARK: OpenLyrics

    private let openLyrics = """
    <?xml version="1.0" encoding="UTF-8"?>
    <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.9" createdIn="OpenLP 3.0">
      <properties>
        <titles><title>Amazing Grace</title><title>Amazing Grace (New Britain)</title></titles>
        <authors><author type="words">John Newton</author><author>John P. Rees</author></authors>
        <copyright>Public Domain</copyright>
        <ccliNo>22025</ccliNo>
        <verseOrder>v1 v2 c v2</verseOrder>
      </properties>
      <lyrics>
        <verse name="v1" lang="en">
          <lines><chord root="G"/>Amazing grace! How sweet the sound<br/>
            That saved a <chord root="D">wretch</chord> like me!</lines>
          <lines>I once was lost, but now am found;<br/>Was blind, but now I see.<comment>repeat softly</comment></lines>
        </verse>
        <verse name="v1" lang="es">
          <lines>Sublime gracia del Señor</lines>
        </verse>
        <verse name="v2" lang="en">
          <lines>'Twas grace that taught my heart to fear,<br/>And grace my fears relieved;</lines>
        </verse>
        <verse name="c" lang="en">
          <lines><line>Praise God, praise God</line><line>Praise God</line></lines>
        </verse>
      </lyrics>
    </song>
    """

    func testOpenLyrics() throws {
        let song = try parse(openLyrics, "amazing.xml")
        XCTAssertEqual(song.title, "Amazing Grace")
        XCTAssertEqual(song.info, SongInfo(authors: ["John Newton", "John P. Rees"], copyright: "Public Domain", ccliNumber: "22025"))
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Verse 2", "Chorus"], "The Spanish translation is skipped")
        XCTAssertEqual(song.sections[0].slides, [
            ["Amazing grace! How sweet the sound", "That saved a wretch like me!"],
            ["I once was lost, but now am found;", "Was blind, but now I see."],
        ])
        XCTAssertEqual(song.sections[2].slides, [["Praise God, praise God", "Praise God"]])
        XCTAssertEqual(song.arrangement?.groups, ["Verse 1", "Verse 2", "Chorus", "Verse 2"])
    }

    func testOpenLyricsVerseNames() {
        XCTAssertEqual(OpenLyricsParser.label(forVerseName: "v1"), "Verse 1")
        XCTAssertEqual(OpenLyricsParser.label(forVerseName: "c"), "Chorus")
        XCTAssertEqual(OpenLyricsParser.label(forVerseName: "p2"), "Pre-Chorus 2")
        XCTAssertEqual(OpenLyricsParser.label(forVerseName: "v1a"), "Verse 1a")
        XCTAssertEqual(OpenLyricsParser.label(forVerseName: "B"), "Bridge")
        XCTAssertEqual(OpenLyricsParser.label(forVerseName: "x1"), "X1")
    }

    func testBrokenOpenLyricsSaysSo() {
        XCTAssertThrowsError(try parse("<song><lyrics><verse name=\"v1\"><lines>A</verse></song>", "broken.xml")) { error in
            guard case .malformed = error as? SongImporter.ImportError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try parse("<?xml version=\"1.0\"?><bible/>", "other.xml")) { error in
            XCTAssertEqual(error as? SongImporter.ImportError, .unreadable)
        }
    }

    // MARK: ChordPro

    func testChordPro() throws {
        let text = """
        {title: Holy, Holy, Holy}
        {artist: Reginald Heber}
        {composer: John B. Dykes}
        {copyright: Public Domain}
        {ccli: 1156}
        # A comment

        {start_of_verse}
        [D]Holy, holy, [Bm]holy! [G]Lord God Al[D]mighty!
        Early in the morning our song shall rise to Thee;

        Holy, holy, holy, merciful and mighty!
        {end_of_verse}

        {start_of_tab}
        e|---0---|
        {end_of_tab}

        {soc: Refrain}
        God in three persons, blessed Trinity!
        {eoc}

        {sov}
        Holy, holy, holy! All the saints adore Thee,
        {eov}

        {chorus}
        """
        let song = try parse(text, "holy.cho")
        XCTAssertEqual(song.title, "Holy, Holy, Holy")
        XCTAssertEqual(song.info, SongInfo(authors: ["Reginald Heber", "John B. Dykes"], copyright: "Public Domain", ccliNumber: "1156"))
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Refrain", "Verse 2"])
        XCTAssertEqual(song.sections[0].slides, [
            ["Holy, holy, holy! Lord God Almighty!", "Early in the morning our song shall rise to Thee;"],
            ["Holy, holy, holy, merciful and mighty!"],
        ])
        XCTAssertEqual(song.arrangement?.groups, ["Verse 1", "Refrain", "Verse 2", "Refrain"], "{chorus} sings it again")
    }

    func testChordProWithCommentsForSectionsAndNoTitle() throws {
        let text = """
        {c: Verse 1}
        [G]Amazing grace
        {c: Chorus}
        [C]My chains are gone
        {start_of_verse label="Verse 2"}
        The Lord has promised good to me
        {end_of_verse}
        """
        let song = try parse(text, "My Chains.chordpro")
        XCTAssertEqual(song.title, "My Chains", "Named after the file")
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Chorus", "Verse 2"])
        XCTAssertNil(song.arrangement, "Sung in file order")
    }

    func testChordProRecognisedInATextFile() throws {
        let song = try parse("{title: Doxology}\n[G]Praise God from whom all blessings flow", "doxology.txt")
        XCTAssertEqual(song.title, "Doxology")
        XCTAssertEqual(song.sections.first?.slides, [["Praise God from whom all blessings flow"]])
    }

    // MARK: SongSelect

    func testSongSelectLyrics() throws {
        let text = """
        Amazing Grace

        Verse 1
        Amazing grace how sweet the sound
        That saved a wretch like me

        I once was lost but now am found
        Was blind but now I see

        Chorus
        Praise God

        Misc 1
        Amen

        CCLI Song # 22025
        John Newton | John P. Rees
        Public Domain
        For use solely with the SongSelect® Terms of Use. All rights reserved. www.ccli.com
        CCLI License # 1234567
        """
        let song = try parse(text, "AmazingGrace.txt")
        XCTAssertEqual(song.title, "Amazing Grace")
        XCTAssertEqual(song.info, SongInfo(authors: ["John Newton", "John P. Rees"], copyright: "Public Domain", ccliNumber: "22025"))
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Chorus", "Misc 1"])
        XCTAssertEqual(song.sections[0].slides.count, 2)
        XCTAssertEqual(song.slideCount, 4, "The footer isn't a slide")
        XCTAssertEqual(song.licenseNumber, "1234567", "The church's licence, kept apart from the song's credits")
    }

    func testSongSelectCopyrightLine() throws {
        let text = "Song\n\nVerse\nWords\n\nCCLI Song # 4768151\nChris Tomlin | Louie Giglio\n© 2006 sixsteps Music (Admin. by Capitol CMG Publishing)\n"
        let song = try parse(text, "song.txt")
        XCTAssertEqual(song.info.copyright, "2006 sixsteps Music (Admin. by Capitol CMG Publishing)")
        XCTAssertEqual(song.info.authors, ["Chris Tomlin", "Louie Giglio"])
    }

    func testSongPro() throws {
        let text = """
        [File]
        Type=SongPro
        Version=3.1
        [S A22025]
        Title=Amazing Grace
        Author=John Newton | John P. Rees
        Copyright=Public Domain
        Fields=Verse 1/tVerse 2
        Words=Amazing grace how sweet the sound/nThat saved a wretch like me/n/nI once was lost/tTwas grace that taught/nMy heart to fear
        """
        let song = try parse(text, "AmazingGrace.usr")
        XCTAssertEqual(song.title, "Amazing Grace")
        XCTAssertEqual(song.info, SongInfo(authors: ["John Newton", "John P. Rees"], copyright: "Public Domain", ccliNumber: "22025"))
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Verse 2"])
        XCTAssertEqual(song.sections[0].slides, [["Amazing grace how sweet the sound", "That saved a wretch like me"], ["I once was lost"]])
    }

    // MARK: Plain text and encodings

    func testPlainLyricsAndEncodings() throws {
        let text = "Coro\nAleluya, aleluya\n\nVerso 1\nCantaré al Señor"
        let song = try parse(text, "Aleluya.txt")
        XCTAssertEqual(song.title, "Aleluya")
        XCTAssertEqual(song.sections.map(\.label), ["Coro", "Verso 1"])

        // Windows Latin 1, as older song files are saved.
        let latin1 = try XCTUnwrap(text.data(using: .windowsCP1252))
        XCTAssertEqual(try SongImporter.parse(latin1, fileName: "Aleluya.txt").sections, song.sections)
        // UTF-8 with a byte order mark.
        XCTAssertEqual(try SongImporter.parse(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8), fileName: "Aleluya.txt").sections,
                       song.sections)

        XCTAssertThrowsError(try parse("\n\n  \n", "empty.txt")) { XCTAssertEqual($0 as? SongImporter.ImportError, .noLyrics) }
        XCTAssertThrowsError(try SongImporter.parse(Data([0x00, 0x01, 0xFF, 0x00]), fileName: "x.bin")) {
            XCTAssertEqual($0 as? SongImporter.ImportError, .unreadable)
        }
    }

    // MARK: Building slides

    func testSlidesSplitLongSectionsAndNumberRepeatedLabels() throws {
        var song = ImportedSong(title: "T", sections: [
            .init(label: "Chorus", slides: [["a", "b", "c"]]),
            .init(label: "Verse", slides: [["d"]]),
            .init(label: "Chorus", slides: [["e"]]),
        ], order: ["Chorus", "Verse", "Chorus"])
        song.numberRepeatedLabels()
        XCTAssertEqual(song.sections.map(\.label), ["Chorus 1", "Verse", "Chorus 2"])
        XCTAssertEqual(song.order, ["Chorus 1", "Verse", "Chorus 1"])

        let slides = song.slides(maxLinesPerSlide: 2)
        XCTAssertEqual(slides.map(\.primaryText), ["a\nb", "c", "d", "e"])
        XCTAssertEqual(slides.map(\.label), ["Chorus 1", "Chorus 1", "Verse", "Chorus 2"])
    }

    func testSongInfoTidying() {
        XCTAssertEqual(SongInfo.authors(from: "Chris Tomlin | John Newton; Louie Giglio, "), ["Chris Tomlin", "John Newton", "Louie Giglio"])
        XCTAssertEqual(SongInfo.copyright(from: "Copyright © 2006 sixsteps"), "2006 sixsteps")
        XCTAssertEqual(SongInfo.ccliNumber(from: "CCLI Song # 4768151"), "4768151")
        XCTAssertTrue(SongInfo().isEmpty)
    }

    // MARK: Coordinator

    @MainActor
    func testImportSongsAddsThemWithCreditsAndOrderAsOneUndo() throws {
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T", presentations: [], playlist: PlaylistDocument(title: "S")))
        let amazing = try parse(openLyrics, "amazing.xml")
        let plain = try parse("Words", "Plain.txt")
        let items = coordinator.importSongs([amazing, plain], maxLinesPerSlide: 1)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(coordinator.project.playlist.items, items)
        let presentation = try XCTUnwrap(coordinator.project.presentation(withID: items[0].presentationID))
        XCTAssertEqual(presentation.title, "Amazing Grace")
        XCTAssertEqual(presentation.song, amazing.info)
        XCTAssertEqual(presentation.slides.count, 8, "Split to one line a slide")
        XCTAssertEqual(presentation.activeArrangement?.groups, ["Verse 1", "Verse 2", "Chorus", "Verse 2"])
        XCTAssertNil(coordinator.project.presentation(withID: items[1].presentationID)?.song, "No credits, no song details")
        XCTAssertEqual(coordinator.project.presentation(withID: items[1].presentationID)?.kind, .song, "Still a song")
        XCTAssertEqual(coordinator.undoActionName, "Import Songs")

        coordinator.undo()
        XCTAssertTrue(coordinator.project.presentations.isEmpty)
        XCTAssertTrue(coordinator.importSongs([]).isEmpty)
    }

    @MainActor
    func testSetSongInfoTidiesAndClears() throws {
        let presentation = PresentationDocument(title: "Song", slides: [.text("a")])
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T", presentations: [presentation],
                                                                           playlist: PlaylistDocument(title: "S")))
        XCTAssertEqual(coordinator.setSongInfo(SongInfo(authors: [" A ", ""], copyright: " 2001 X ", ccliNumber: "# 12"),
                                               presentationID: presentation.id), .applied)
        XCTAssertEqual(coordinator.project.presentation(withID: presentation.id)?.song,
                       SongInfo(authors: ["A"], copyright: "2001 X", ccliNumber: "12"))
        coordinator.setSongInfo(SongInfo(), presentationID: presentation.id)
        XCTAssertNil(coordinator.project.presentation(withID: presentation.id)?.song)
        XCTAssertEqual(coordinator.setSongInfo(SongInfo(), presentationID: coordinator.project.props.id), .rejected(.unknownPresentation))
    }

    func testSongDetailsRoundTripAndFormat6FilesHaveNone() throws {
        var presentation = PresentationDocument(title: "Song", slides: [.text("a")])
        presentation.song = SongInfo(authors: ["A"], copyright: "B", ccliNumber: "1")
        let data = try JSONEncoder().encode(presentation)
        XCTAssertEqual(try JSONDecoder().decode(PresentationDocument.self, from: data), presentation)

        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["song"] = nil
        let legacy = try JSONDecoder().decode(PresentationDocument.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.song)
        XCTAssertEqual(ProjectDocument.currentSchemaVersion, 9)
    }

    func testKindRoundTripsAndFormat7FilesGetAGuess() throws {
        let caption = SlideDocument(elements: [.text(TextElement(text: "John 3:16 · KJV", role: .caption))])
        var labelled = SlideDocument.text("Amazing grace")
        labelled.label = "Verse 1"
        let cases: [(PresentationDocument, PresentationKind)] = [
            (PresentationDocument(title: "Deck", slides: [.text("Welcome")]), .presentation),
            (PresentationDocument(title: "Song", slides: [labelled]), .song),
            (PresentationDocument(title: "Credits", slides: [.text("a")], song: SongInfo(authors: ["A"])), .song),
            (PresentationDocument(title: "Ordered", slides: [.text("a")], arrangements: [Arrangement(name: "O", groups: [])]), .song),
            (PresentationDocument(title: "John 3:16", slides: [caption, caption]), .scripture),
            (PresentationDocument(title: "Empty", slides: []), .presentation),
        ]
        for (presentation, guess) in cases {
            var saved = presentation
            saved.kind = .scripture
            let data = try JSONEncoder().encode(saved)
            XCTAssertEqual(try JSONDecoder().decode(PresentationDocument.self, from: data).kind, .scripture)

            var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            old["kind"] = nil
            let legacy = try JSONDecoder().decode(PresentationDocument.self, from: JSONSerialization.data(withJSONObject: old))
            XCTAssertEqual(legacy.kind, guess, presentation.title)
        }
    }

    @MainActor
    func testSetKindChangesAndUndoes() throws {
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let item = coordinator.addPresentation(title: "Untitled")
        let id = item.presentationID
        XCTAssertEqual(coordinator.project.presentation(withID: id)?.kind, .presentation)

        XCTAssertEqual(coordinator.setKind(.song, presentationID: id), .applied)
        XCTAssertEqual(coordinator.project.presentation(withID: id)?.kind, .song)
        XCTAssertEqual(coordinator.undoActionName, "Change Type")
        coordinator.undo()
        XCTAssertEqual(coordinator.project.presentation(withID: id)?.kind, .presentation)
        XCTAssertEqual(coordinator.setKind(.song, presentationID: coordinator.project.props.id), .rejected(.unknownPresentation))
    }
}
