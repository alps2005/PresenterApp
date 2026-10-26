import Foundation

/// The words in an RTF document, as ProPresenter stores a slide's text (Apple's CocoaRTF): formatting and header
/// tables dropped, paragraph and line breaks kept as new lines, accents and other characters from their escapes.
enum RTFText {
    static func plainText(_ data: Data) -> String {
        // RTF is 7-bit text; anything above that comes through escapes.
        let characters = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        /// Whether each open group is a destination to skip (font and colour tables, document info…).
        var skipping: [Bool] = [false]
        var pendingHighSurrogate: UInt32?

        func append(_ scalar: Unicode.Scalar) {
            guard skipping.last != true else { return }
            output.append(scalar)
        }

        func appendUnicode(_ value: Int) {
            let code = UInt32(value < 0 ? value + 65_536 : value)
            if (0xD800...0xDBFF).contains(code) {
                pendingHighSurrogate = code
                return
            }
            var scalar: Unicode.Scalar?
            if let high = pendingHighSurrogate, (0xDC00...0xDFFF).contains(code) {
                scalar = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (code - 0xDC00))
            } else {
                scalar = Unicode.Scalar(code)
            }
            pendingHighSurrogate = nil
            if let scalar, skipping.last != true { output.append(scalar) }
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "{":
                skipping.append(skipping.last ?? false)
                index += 1
                // A group that starts with \* or a header table is a destination the text doesn't include.
                let rest = String(String.UnicodeScalarView(characters[index..<min(index + 24, characters.count)]))
                if rest.hasPrefix("\\*") || ["\\fonttbl", "\\colortbl", "\\stylesheet", "\\info", "\\pict", "\\header",
                                            "\\footer", "\\expandedcolortbl"].contains(where: rest.hasPrefix) {
                    skipping[skipping.count - 1] = true
                }
            case "}":
                if skipping.count > 1 { skipping.removeLast() }
                index += 1
            case "\\":
                index += 1
                guard index < characters.count else { break }
                let next = characters[index]
                if next == "\\" || next == "{" || next == "}" {
                    append(next)
                    index += 1
                } else if next == "'" {
                    let hex = String(String.UnicodeScalarView(characters[min(index + 1, characters.count)..<min(index + 3, characters.count)]))
                    index += 3
                    if let byte = UInt8(hex, radix: 16),
                       let text = String(data: Data([byte]), encoding: .windowsCP1252), let scalar = text.unicodeScalars.first {
                        append(scalar)
                    }
                } else if next == "\n" || next == "\r" {
                    append("\n")
                    index += 1
                } else if next == "~" {
                    append(" ")
                    index += 1
                } else if next == "_" {
                    append("-")
                    index += 1
                } else if next.properties.isAlphabetic {
                    var word = ""
                    while index < characters.count, characters[index].properties.isAlphabetic, characters[index].isASCII {
                        word.unicodeScalars.append(characters[index])
                        index += 1
                    }
                    var parameter = ""
                    if index < characters.count, characters[index] == "-" {
                        parameter = "-"
                        index += 1
                    }
                    while index < characters.count, ("0"..."9").contains(characters[index]) {
                        parameter.unicodeScalars.append(characters[index])
                        index += 1
                    }
                    // One space after a control word only ends it.
                    if index < characters.count, characters[index] == " " { index += 1 }
                    switch word {
                    case "par", "line":
                        append("\n")
                    case "tab":
                        append("\t")
                    case "u":
                        if let value = Int(parameter) {
                            appendUnicode(value)
                            // Skip the stand-in: one character, or one \'xx escape.
                            if index < characters.count, characters[index] == "\\", index + 1 < characters.count,
                               characters[index + 1] == "'" {
                                index += 4
                            } else if index < characters.count, characters[index] != "\\", characters[index] != "{",
                                      characters[index] != "}" {
                                index += 1
                            }
                        }
                    default:
                        break
                    }
                } else {
                    // Other control symbols (\- optional hyphen, \| …) add nothing.
                    index += 1
                }
            case "\n", "\r":
                // Raw line ends in RTF are only formatting of the file.
                index += 1
            default:
                append(character)
                index += 1
            }
        }
        return String(output)
    }
}
