import XCTest
@testable import PresenterCore

/// Builds Protocol Buffers bytes the way ProPresenter writes them, for test files. Each call returns a new writer.
private struct ProtobufWriter {
    private(set) var data = Data()

    private mutating func varint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            data.append(byte)
        } while value != 0
    }

    func int(_ number: Int, _ value: UInt64) -> Self {
        var copy = self
        copy.varint(UInt64(number) << 3)
        copy.varint(value)
        return copy
    }

    func bytes(_ number: Int, _ value: Data) -> Self {
        var copy = self
        copy.varint(UInt64(number) << 3 | 2)
        copy.varint(UInt64(value.count))
        copy.data.append(value)
        return copy
    }

    func string(_ number: Int, _ value: String) -> Self { bytes(number, Data(value.utf8)) }
    func message(_ number: Int, _ value: ProtobufWriter) -> Self { bytes(number, value.data) }
}

private func message(_ build: (ProtobufWriter) -> ProtobufWriter) -> ProtobufWriter {
    build(ProtobufWriter())
}

private func uuid(_ id: String) -> ProtobufWriter {
    message { $0.string(1, id) }
}

/// A slide cue whose text is `rtf`, as Presentation.cues → Cue → Action → SlideType → PresentationSlide → Slide →
/// Element → Graphics.Element → Text.rtf_data.
private func cue(_ id: String, rtf: String, translation: String? = nil) -> ProtobufWriter {
    func element(_ rtf: String) -> ProtobufWriter {
        message { $0.message(1, message { $0.string(2, "Text").message(13, message { $0.string(5, rtf) }) }) }
    }
    var slide = ProtobufWriter().message(1, element(rtf))
    if let translation { slide = slide.message(1, element(translation)) }
    let action = message { $0.int(9, 11).message(23, message { $0.message(2, message { $0.message(1, slide) }) }) }
    return message { $0.message(1, uuid(id)).string(2, "").message(10, action) }
}

private func group(_ id: String, _ name: String, cues: [String]) -> ProtobufWriter {
    cues.reduce(ProtobufWriter().message(1, message { $0.message(1, uuid(id)).string(2, name) })) { $0.message(2, uuid($1)) }
}

private func rtf(_ body: String) -> String {
    #"{\rtf1\ansi\ansicpg1252\cocoartf2639 {\fonttbl\f0\fnil\fcharset0 HelveticaNeue;}{\colortbl;\red255\green255\blue255;}{\*\expandedcolortbl;;}\pard\pardirnatural\qc\partightenfactor0 \f0\fs120 \cf1 \CocoaLigature0 "# + body + "}"
}

final class ProPresenterImportTests: XCTestCase {
    func testRTFText() {
        XCTAssertEqual(RTFText.plainText(Data(rtf(#"Amazing grace\par How sweet"#).utf8)), "Amazing grace\nHow sweet")
        XCTAssertEqual(RTFText.plainText(Data(rtf("Line one\\\nLine two").utf8)), "Line one\nLine two", "Backslash-newline is a soft return")
        XCTAssertEqual(RTFText.plainText(Data(rtf(#"Coraz\'f3n, se\u241?or"#).utf8)), "Corazón, señor")
        XCTAssertEqual(RTFText.plainText(Data(rtf(#"\{braces\} and \\ back"#).utf8)), "{braces} and \\ back")
        XCTAssertEqual(RTFText.plainText(Data(rtf(#"\u-10179?\u-8704? praise"#).utf8)), "😀 praise", "Surrogate pairs")
        XCTAssertEqual(RTFText.plainText(Data(rtf(#"Tab\tab end"#).utf8)), "Tab\tend")
    }

    func testProtobufReader() throws {
        let data = message { $0.string(3, "Name").int(5, 300).message(14, message { $0.int(6, 22025) }) }.data
        let read = try ProtobufMessage(data)
        XCTAssertEqual(read.string(3), "Name")
        XCTAssertEqual(read.varint(5), 300)
        XCTAssertEqual(read.message(14)?.varint(6), 22025)
        XCTAssertThrowsError(try ProtobufMessage(Data([0x0A, 0x05, 0x41])), "A length past the end")
        XCTAssertThrowsError(try ProtobufMessage(Data("{title: Song}".utf8)), "ChordPro text isn't protobuf")
    }

    func testSongWithGroupsArrangementAndCCLI() throws {
        let file = message { writer in
            writer.string(3, "Amazing Grace")
                .message(10, uuid("arr-1"))
                .message(11, message { $0.message(1, uuid("arr-0")).string(2, "Short").message(3, uuid("g-v")) })
                .message(11, message { $0.message(1, uuid("arr-1")).string(2, "Full")
                    .message(3, uuid("g-v")).message(3, uuid("g-c")).message(3, uuid("g-v2")).message(3, uuid("g-c")) })
                .message(12, group("g-v", "Verse 1", cues: ["c1", "c2"]))
                .message(12, group("g-c", "Chorus", cues: ["c3"]))
                .message(12, group("g-v2", "Verse 2", cues: ["c4"]))
                .message(13, cue("c1", rtf: rtf(#"Amazing grace\par how sweet the sound"#), translation: rtf("Sublime gracia")))
                .message(13, cue("c2", rtf: rtf("That saved a wretch like me")))
                .message(13, cue("c3", rtf: rtf("My chains are gone")))
                .message(13, cue("c4", rtf: rtf("Twas grace")))
                .message(13, cue("c5", rtf: rtf("Amen")))
                .message(14, message { $0.string(1, "John Newton, Chris Tomlin").string(3, "Amazing Grace")
                    .string(4, "sixsteps Music").int(5, 2006).int(6, 4768151) })
        }.data

        let song = try SongImporter.parse(file, fileName: "Amazing Grace.pro")
        XCTAssertEqual(song.title, "Amazing Grace")
        XCTAssertEqual(song.info, SongInfo(authors: ["John Newton", "Chris Tomlin"], copyright: "2006 sixsteps Music", ccliNumber: "4768151"))
        XCTAssertEqual(song.sections.map(\.label), ["Verse 1", "Chorus", "Verse 2", nil], "A slide in no group comes last")
        XCTAssertEqual(song.sections[0].slides, [["Amazing grace", "how sweet the sound"], ["That saved a wretch like me"]],
                       "The first text element; the second is a translation")
        XCTAssertEqual(song.order, ["Verse 1", "Chorus", "Verse 2", "Chorus"], "The selected arrangement")
        XCTAssertEqual(song.arrangement?.groups, ["Verse 1", "Chorus", "Verse 2", "Chorus"])
    }

    func testRepeatedGroupNamesAreNumbered() throws {
        let file = message { writer in
            writer.string(3, "Song")
                .message(11, message { $0.message(1, uuid("a")).message(3, uuid("g2")).message(3, uuid("g1")) })
                .message(12, group("g1", "Chorus", cues: ["c1"]))
                .message(12, group("g2", "Chorus", cues: ["c2"]))
                .message(13, cue("c1", rtf: rtf("One")))
                .message(13, cue("c2", rtf: rtf("Two")))
        }.data
        let song = try SongImporter.parse(file, fileName: "Song.pro")
        XCTAssertEqual(song.sections.map(\.label), ["Chorus 1", "Chorus 2"])
        XCTAssertEqual(song.order, ["Chorus 2", "Chorus 1"], "The only arrangement, by group, not by name")
        XCTAssertEqual(song.info, SongInfo())
    }

    func testChordProDotProStillReadsAsChordPro() throws {
        let song = try SongImporter.parse(Data("{title: Doxology}\n[G]Praise God from whom".utf8), fileName: "doxology.pro")
        XCTAssertEqual(song.title, "Doxology")
        XCTAssertEqual(song.sections.first?.slides, [["Praise God from whom"]])
    }

    func testAProFileWithoutWordsIsNotASong() {
        let file = message { $0.string(3, "Announcements").message(13, message { $0.message(1, uuid("c")) }) }.data
        XCTAssertNil(ProPresenterParser.parse(file))
        XCTAssertThrowsError(try SongImporter.parse(file, fileName: "Announcements.pro"))
    }
}
