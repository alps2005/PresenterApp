import Foundation

/// What an audience output shows, like ProPresenter's looks: each layer can be left out, the background can become a
/// plain key colour (green for a video keyer), and the slide's words can be restyled with another theme (a lower
/// third for a livestream). Kept per Mac with the outputs' screens, so each venue sets up its own.
public struct OutputLook: Codable, Equatable, Sendable {
    public var showsBackground: Bool
    public var showsSlide: Bool
    public var showsProps: Bool
    public var showsMessages: Bool
    /// What fills the background while it's hidden. Nil is black.
    public var keyColor: RGBAColor?
    /// The theme the live slide's words are restyled with on this output. Nil keeps them as they are. Text the
    /// operator formatted by hand keeps its look, as it does when a presentation changes theme.
    public var themeID: UUID?

    public init(showsBackground: Bool = true, showsSlide: Bool = true, showsProps: Bool = true,
                showsMessages: Bool = true, keyColor: RGBAColor? = nil, themeID: UUID? = nil) {
        self.showsBackground = showsBackground
        self.showsSlide = showsSlide
        self.showsProps = showsProps
        self.showsMessages = showsMessages
        self.keyColor = keyColor
        self.themeID = themeID
    }

    /// Everything, as the operator's previews show it.
    public static let everything = OutputLook()

    public var isEverything: Bool { self == .everything }

    /// What this output shows of the audience scene. Blackout stays black on every output.
    public func scene(from scene: AudienceScene, theme: Theme?) -> AudienceScene {
        let hidden = SlideBackground.color(keyColor ?? .black)
        switch scene {
        case .black:
            return .black
        case .empty:
            return showsBackground ? .empty : .background(hidden)
        case .background(let background):
            return .background(showsBackground ? background : hidden)
        case .slide(let rendered):
            let background = showsBackground ? rendered.background : hidden
            guard showsSlide else { return background.map(AudienceScene.background) ?? .empty }
            let slide = theme.map { $0.applied(to: rendered.slide) } ?? rendered.slide
            return .slide(RenderedSlide(slide: slide, background: background))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case showsBackground, showsSlide, showsProps, showsMessages, keyColor, themeID
    }

    /// Fields added later decode with their defaults, so a look saved by an older version still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsBackground = try container.decodeIfPresent(Bool.self, forKey: .showsBackground) ?? true
        showsSlide = try container.decodeIfPresent(Bool.self, forKey: .showsSlide) ?? true
        showsProps = try container.decodeIfPresent(Bool.self, forKey: .showsProps) ?? true
        showsMessages = try container.decodeIfPresent(Bool.self, forKey: .showsMessages) ?? true
        keyColor = try container.decodeIfPresent(RGBAColor.self, forKey: .keyColor)
        themeID = try container.decodeIfPresent(UUID.self, forKey: .themeID)
    }
}
