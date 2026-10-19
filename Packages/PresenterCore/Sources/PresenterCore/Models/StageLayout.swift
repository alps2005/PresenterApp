import Foundation

/// A design for the stage display: boxes placed on the screen, each showing one thing (the live words, the next
/// slide, the clock…), like ProPresenter's stage layouts. The stage display uses the one chosen in `StageSettings`;
/// without one it uses the standard look.
public struct StageLayout: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Drawn in order, so later regions sit on top.
    public var regions: [StageRegion]
    public var background: RGBAColor

    public init(id: UUID = UUID(), name: String, regions: [StageRegion] = [], background: RGBAColor = .black) {
        self.id = id
        self.name = name
        self.regions = regions
        self.background = background
    }

    public func region(withID regionID: UUID) -> StageRegion? {
        regions.first { $0.id == regionID }
    }
}

/// One box on a stage layout.
public struct StageRegion: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// The live slide's words.
        case liveText
        /// The next slide's words, under a "NEXT" heading with its group label.
        case nextText
        /// The live slide as the audience sees it.
        case liveSlide
        /// The next slide as the audience will see it.
        case nextSlide
        case clock
        /// A timer's value under its name. Nil shows the timer chosen for the stage.
        case timer(UUID?)
        /// The live slide's notes.
        case notes
        /// The message to the stage, on a yellow bar. Empty while there's no message.
        case message
        /// Fixed words, such as a reminder for the band.
        case text(String)

        public var title: String {
            switch self {
            case .liveText: "Live Words"
            case .nextText: "Next Words"
            case .liveSlide: "Live Slide"
            case .nextSlide: "Next Slide"
            case .clock: "Clock"
            case .timer: "Timer"
            case .notes: "Notes"
            case .message: "Stage Message"
            case .text: "Text"
            }
        }

        /// Every kind, for the Add menu.
        public static let all: [Kind] = [.liveText, .nextText, .liveSlide, .nextSlide, .clock, .timer(nil), .notes, .message, .text("Text")]

        /// True when the region draws text, so it has a size, colour and alignment.
        public var hasText: Bool {
            switch self {
            case .liveSlide, .nextSlide: false
            default: true
            }
        }
    }

    public let id: UUID
    public var kind: Kind
    /// Where the box sits, as fractions of the stage screen.
    public var frame: NormalizedRect
    /// Points on a 1080-point-tall screen; the text shrinks to fit its box.
    public var fontSize: Double
    public var color: RGBAColor
    public var alignment: HorizontalTextAlignment
    /// The small heading above a timer ("SERMON") or the next words ("NEXT · CHORUS").
    public var showsLabel: Bool

    public static let fontSizeRange: ClosedRange<Double> = 16...300

    public init(
        id: UUID = UUID(),
        kind: Kind,
        frame: NormalizedRect,
        fontSize: Double = 72,
        color: RGBAColor = .white,
        alignment: HorizontalTextAlignment = .leading,
        showsLabel: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.showsLabel = showsLabel
    }

    /// The timer this region shows, given the stage's chosen timer.
    public func timerID(stageTimerID: UUID?) -> UUID? {
        guard case .timer(let own) = kind else { return nil }
        return own ?? stageTimerID
    }
}

extension RGBAColor {
    static let stageYellow = RGBAColor(red: 1, green: 0.84, blue: 0)
    static let stageCyan = RGBAColor(red: 0.35, green: 0.85, blue: 1)
    static let stageGray = RGBAColor(red: 0.6, green: 0.6, blue: 0.6)
}

extension StageLayout {
    /// A layout like the standard look, as a starting point for a new one.
    public static func standard(name: String = "Standard") -> StageLayout {
        StageLayout(name: name, regions: [
            StageRegion(kind: .clock, frame: NormalizedRect(x: 0.03, y: 0.04, width: 0.4, height: 0.1), fontSize: 72),
            StageRegion(kind: .timer(nil), frame: NormalizedRect(x: 0.57, y: 0.03, width: 0.4, height: 0.12), fontSize: 72,
                        alignment: .trailing),
            StageRegion(kind: .liveText, frame: NormalizedRect(x: 0.03, y: 0.18, width: 0.94, height: 0.46), fontSize: 92),
            StageRegion(kind: .nextText, frame: NormalizedRect(x: 0.03, y: 0.66, width: 0.94, height: 0.18), fontSize: 52,
                        color: .stageYellow),
            StageRegion(kind: .notes, frame: NormalizedRect(x: 0.03, y: 0.86, width: 0.94, height: 0.11), fontSize: 40,
                        color: .stageCyan),
            StageRegion(kind: .message, frame: NormalizedRect(x: 0.03, y: 0.16, width: 0.94, height: 0.09), fontSize: 54,
                        color: .black),
        ])
    }

    /// The layouts a project starts with.
    public static func presets() -> [StageLayout] {
        [
            // For singers and the band: big words, what's coming, and the time.
            StageLayout(name: "Lyrics", regions: [
                StageRegion(kind: .liveText, frame: NormalizedRect(x: 0.03, y: 0.04, width: 0.94, height: 0.6), fontSize: 120),
                StageRegion(kind: .nextText, frame: NormalizedRect(x: 0.03, y: 0.68, width: 0.94, height: 0.22), fontSize: 64,
                            color: .stageYellow),
                StageRegion(kind: .clock, frame: NormalizedRect(x: 0.72, y: 0.91, width: 0.25, height: 0.07), fontSize: 40,
                            color: .stageGray, alignment: .trailing),
                StageRegion(kind: .message, frame: NormalizedRect(x: 0.03, y: 0.04, width: 0.94, height: 0.1), fontSize: 60,
                            color: .black),
            ]),
            // For the preacher: the time left, notes, and the slide's words small.
            StageLayout(name: "Speaker", regions: [
                StageRegion(kind: .clock, frame: NormalizedRect(x: 0.03, y: 0.04, width: 0.44, height: 0.2), fontSize: 110),
                StageRegion(kind: .timer(nil), frame: NormalizedRect(x: 0.53, y: 0.03, width: 0.44, height: 0.22), fontSize: 120,
                            alignment: .trailing),
                StageRegion(kind: .notes, frame: NormalizedRect(x: 0.03, y: 0.3, width: 0.94, height: 0.42), fontSize: 64,
                            color: .stageCyan),
                StageRegion(kind: .liveText, frame: NormalizedRect(x: 0.03, y: 0.76, width: 0.94, height: 0.2), fontSize: 48),
                StageRegion(kind: .message, frame: NormalizedRect(x: 0.03, y: 0.28, width: 0.94, height: 0.12), fontSize: 64,
                            color: .black),
            ]),
            // For whoever follows the visuals: the live and next slides as pictures.
            StageLayout(name: "Slides", regions: [
                StageRegion(kind: .liveSlide, frame: NormalizedRect(x: 0.03, y: 0.05, width: 0.6, height: 0.6)),
                StageRegion(kind: .nextSlide, frame: NormalizedRect(x: 0.66, y: 0.05, width: 0.31, height: 0.31)),
                StageRegion(kind: .clock, frame: NormalizedRect(x: 0.66, y: 0.4, width: 0.31, height: 0.1), fontSize: 64),
                StageRegion(kind: .timer(nil), frame: NormalizedRect(x: 0.66, y: 0.52, width: 0.31, height: 0.13), fontSize: 64),
                StageRegion(kind: .notes, frame: NormalizedRect(x: 0.03, y: 0.7, width: 0.94, height: 0.26), fontSize: 48,
                            color: .stageCyan),
                StageRegion(kind: .message, frame: NormalizedRect(x: 0.03, y: 0.7, width: 0.94, height: 0.1), fontSize: 54,
                            color: .black),
            ]),
        ]
    }
}
