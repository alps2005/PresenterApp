import XCTest
@testable import PresenterCore

final class PreServiceCheckTests: XCTestCase {
    private let photo = MediaAsset(originalFilename: "Sunrise.jpg", storedFilename: "a.jpg", pixelWidth: 10, pixelHeight: 10)
    private let unused = MediaAsset(originalFilename: "Old.jpg", storedFilename: "b.jpg", pixelWidth: 10, pixelHeight: 10)

    private func check(_ project: ProjectDocument, missing: Set<UUID> = [], fonts: Set<String> = ["Helvetica"],
                       audience: OutputStatus = .fullScreen(displayName: "Projector"),
                       includesOutputOff: Bool = true) -> [PreServiceProblem] {
        PreServiceCheck.problems(in: project, mediaExists: { !missing.contains($0.id) }, installedFonts: fonts,
                                 audience: audience, includesOutputOff: includesOutputOff)
    }

    private func project(_ presentations: [PresentationDocument], library: [PresentationDocument] = []) -> ProjectDocument {
        ProjectDocument(name: "T", presentations: presentations + library,
                        playlist: PlaylistDocument(title: "Sunday", items: presentations.map { PresentationItem(presentationID: $0.id) }),
                        mediaAssets: [photo, unused])
    }

    func testACleanShowHasNoProblems() {
        let welcome = PresentationDocument(title: "Welcome", slides: [.text("Hello")])
        let song = PresentationDocument(title: "Grace", slides: [.text("Amazing grace")], song: SongInfo(ccliNumber: "1"), kind: .song)
        XCTAssertEqual(check(project([welcome, song])), [])
    }

    func testMissingMediaInTheShowOnly() {
        var slide = SlideDocument.text("Hi")
        slide.background = .image(ImageBackground(assetID: photo.id))
        let deck = PresentationDocument(title: "Deck", slides: [slide])
        let old = PresentationDocument(title: "Old", slides: [.text("x")], background: .image(ImageBackground(assetID: unused.id)))
        let p = project([deck], library: [old])
        let problems = check(p, missing: [photo.id, unused.id])
        XCTAssertEqual(problems.map(\.kind), [.missingMedia], "Library items outside the show don't count")
        XCTAssertEqual(problems.first?.message, "“Sunrise.jpg” is missing, used in “Deck”.")
        XCTAssertEqual(problems.first?.itemID, p.playlist.items.first?.id)
    }

    func testMissingMediaInSlideActionsAndThemes() {
        var slide = SlideDocument.text("Hi")
        slide.actions = [.playAudio(track: AudioTrack(assetID: photo.id))]
        XCTAssertEqual(check(project([PresentationDocument(title: "A", slides: [slide])]), missing: [photo.id]).map(\.kind), [.missingMedia])

        var theme = Theme(name: "Photo")
        theme.background = .image(ImageBackground(assetID: unused.id))
        var p = project([PresentationDocument(title: "B", slides: [.text("x")], themeID: theme.id)])
        p.themes.append(theme)
        XCTAssertEqual(check(p, missing: [unused.id]).map(\.kind), [.missingMedia])
    }

    func testMissingFontsOnceEach() {
        var style = TextStyle.default(for: .body)
        style.fontFamily = "Gotham"
        let slide = SlideDocument(elements: [.text(TextElement(text: "A", style: style, overrides: [.style])),
                                             .text(TextElement(text: "B", style: style, overrides: [.style]))])
        let problems = check(project([PresentationDocument(title: "Deck", slides: [slide, slide])]))
        XCTAssertEqual(problems.map(\.kind), [.missingFont])
        XCTAssertTrue(problems[0].message.contains("“Gotham”"))
        XCTAssertEqual(check(project([PresentationDocument(title: "Deck", slides: [slide])]), fonts: ["Gotham"]), [])
    }

    func testThemeFontsCount() {
        var theme = Theme(name: "Fancy")
        theme.body.style.fontFamily = "Brandon"
        var p = project([PresentationDocument(title: "Deck", slides: [.text("Words")], themeID: theme.id)])
        p.themes.append(theme)
        XCTAssertEqual(check(p).map(\.kind), [.missingFont])
    }

    func testOutput() {
        let p = project([])
        XCTAssertEqual(check(p, audience: .off).map(\.kind), [.output])
        XCTAssertEqual(check(p, audience: .off, includesOutputOff: false), [], "At launch the output is turned on later")
        XCTAssertEqual(check(p, audience: .displayMissing(displayName: "Projector"), includesOutputOff: false).map(\.kind), [.output])
        XCTAssertEqual(check(p, audience: .displayHasOperatorWindow(displayName: "Projector")).map(\.kind), [.output])
        XCTAssertEqual(check(p, audience: .windowed), [])
    }

    func testEmptyPresentationsAndSongsWithoutCredits() {
        let untitled = PresentationDocument(title: "", slides: [.text("")])
        let withBackground = PresentationDocument(title: "Picture", slides: [.text("")], background: .color(.black))
        let blankInSong = PresentationDocument(title: "Song", slides: [.text("Words"), .text("")], song: SongInfo(authors: ["A"]), kind: .song)
        let noCredits = PresentationDocument(title: "Mine", slides: [.text("la")], kind: .song)
        let problems = check(project([untitled, withBackground, blankInSong, noCredits]))
        XCTAssertEqual(problems.map(\.kind), [.emptyPresentation, .songWithoutCredits])
        XCTAssertEqual(problems[0].message, "“Untitled” has nothing on its slides.")
        XCTAssertTrue(problems[1].message.hasPrefix("“Mine”"))
    }

    func testProblemsAreSortedByKind() {
        let noCredits = PresentationDocument(title: "Mine", slides: [.text("la")], kind: .song)
        let kinds = check(project([noCredits]), audience: .off).map(\.kind)
        XCTAssertEqual(kinds, [.output, .songWithoutCredits])
    }
}
